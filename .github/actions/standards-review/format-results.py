#!/usr/bin/env python3
"""Format lint-standards.sh JSON output as a Markdown table row per result.

Each result may carry a ``member`` (the monorepo sub-root it was produced in,
``"."`` for the project root). A member other than the root is shown as a
prefix on the check name so one table covers the whole aggregated run.
"""
import json
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


def cell(value):
    """Escape a table cell: no pipes, no line breaks."""
    return str(value).replace("|", "\\|").replace("\n", " ")


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


icons = {"PASS": ":white_check_mark:", "WARN": ":warning:", "FAIL": ":x:"}
for r in results:
    if not isinstance(r, dict):
        continue
    status = r.get("status", "")
    raw_check = r.get("check", "")
    check = cell(raw_check)
    member = r.get("member", "")
    if member and member != ".":
        check = f"{member_cell(member)}: {check}"
    # Every message is repository-controlled input: modules quote file names,
    # link targets, declared member paths and content excerpts from the PR
    # under review, so a hostile PR could otherwise plant a mention, link,
    # image or HTML in the bot's comment. Neutralise all of them, not just
    # the synthetic members check.
    message = inert(r.get("message", ""))[:500]
    icon = icons.get(status, ":grey_question:")
    print(f"| {icon} {status} | {check} | {message} |")
