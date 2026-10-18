#!/usr/bin/env python3
"""Format lint-standards.sh JSON output as a Markdown table row per result.

Each result may carry a ``member`` (the monorepo sub-root it was produced in,
``"."`` for the project root). A member other than the root is shown as a
prefix on the check name so one table covers the whole aggregated run.
"""
import json
import re
import sys

raw = sys.argv[1] if len(sys.argv) > 1 else "{}"
results = []
try:
    data = json.loads(raw)
    if isinstance(data, dict):
        raw_results = data.get("results", [])
        if isinstance(raw_results, list):
            results = raw_results
except (json.JSONDecodeError, ValueError):
    pass


# Every C0/C1-style control character plus the Unicode line/paragraph
# separators. CommonMark treats \r, \n and \r\n as line endings, and a line
# ending anywhere in a cell ends the table row, so whatever follows renders as
# live Markdown outside the row (and outside any code span the cell opened).
CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f\u2028\u2029]")


def cell(value):
    """Escape a table cell: one line, no unescaped pipes.

    Pipes are escaped as ``\\|``. A backslash already in the text would turn
    that into ``\\\\|`` — an escaped backslash followed by a live pipe, which the
    GFM row splitter reads as a cell boundary — so a space is inserted between a
    backslash and a following pipe first.
    """
    text = CONTROL_CHARS.sub(" ", str(value))
    text = re.sub(r"\\(?=\|)", "\\ ", text)
    return text.replace("|", "\\|")


def member_cell(value):
    """Render a member path as an inert literal.

    The member list comes from the PR's own ``.standards.yml``, so it is
    untrusted: ``@org/team`` would ping a team and ``[x](url)`` or
    ``![x](url)`` would inject a link or image into the bot's comment. Mirror
    the action's own sanitising (drop backticks, ``@``, brackets, parentheses
    and angle brackets), cap the length, and show the result in a code span so
    whatever remains is literal Markdown.
    """
    text = inert(value)[:200].strip() or "member"
    return f"`{text}`"


def inert(value):
    """Drop the characters that turn text into a mention, link, image or code span."""
    text = cell(value)
    for ch in "`@[]()<>":
        text = text.replace(ch, "")
    return text


MESSAGE_LIMIT = 500


def message_cell(value):
    """Render a check message as a literal code span.

    Every message is repository-controlled input: modules quote file names,
    link targets, declared member paths and content excerpts from the PR under
    review, so a hostile PR could otherwise plant a mention, link, image or
    HTML in the bot's comment. Deleting ``@[]()<>`` is not enough — GitHub
    autolinks a bare ``https://evil`` — and it mangles legitimate paths such as
    ``packages/@scope/app`` or ``[tool.ruff]``. Inside a code span nothing is
    Markdown-active (no mentions, autolinks, images or HTML), so the text can
    be shown verbatim. Backticks would end the span early, so they become
    apostrophes; ``\\|`` keeps a pipe inside a table cell even within a code
    span (GFM tables). The length is capped so one row cannot flood the comment.
    """
    text = cell(value).replace("`", "'").strip()
    if not text:
        return ""
    if len(text) > MESSAGE_LIMIT:
        text = text[:MESSAGE_LIMIT].rstrip() + " …"
    return f"`{text}`"


icons = {"PASS": ":white_check_mark:", "WARN": ":warning:", "FAIL": ":x:"}

# GitHub rejects comment bodies over 65536 characters, and the action posts the
# whole table in one `gh pr comment` call under continue-on-error. A hostile (or
# merely huge) monorepo can declare enough members to make the aggregate output
# unbounded even with per-message caps, and an oversized body would silently
# lose every warning. Keep the table within a budget that leaves ample headroom
# for the rest of the comment; when it does not fit, drop PASS rows first and
# say explicitly how many rows were omitted.
MAX_ROWS = 200
MAX_BYTES = 50000


def render(r):
    status = r.get("status", "")
    check = cell(r.get("check", ""))
    member = r.get("member", "")
    if member and member != ".":
        check = f"{member_cell(member)}: {check}"
    message = message_cell(r.get("message", ""))
    icon = icons.get(status, ":grey_question:")
    return status, f"| {icon} {status} | {check} | {message} |"


def fits(rows):
    return len(rows) <= MAX_ROWS and sum(len(row.encode("utf-8")) + 1 for row in rows) <= MAX_BYTES


rendered = [render(r) for r in results if isinstance(r, dict)]
rows = [row for _, row in rendered]
omitted = []
if not fits(rows):
    passing = [row for status, row in rendered if status == "PASS"]
    if passing:
        rows = [row for status, row in rendered if status != "PASS"]
        omitted.append(f"{len(passing)} passing")
    if not fits(rows):
        kept = []
        for row in rows:
            if not fits(kept + [row]):
                break
            kept.append(row)
        omitted.append(f"{len(rows) - len(kept)} further")
        rows = kept

for row in rows:
    print(row)
if omitted:
    print(
        f"| :grey_question: TRUNCATED | comment size limit | "
        f"{' and '.join(omitted)} result row(s) not shown; see the workflow log for the full report |"
    )
