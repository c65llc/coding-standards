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


icons = {"PASS": ":white_check_mark:", "WARN": ":warning:", "FAIL": ":x:"}
for r in results:
    if not isinstance(r, dict):
        continue
    status = r.get("status", "")
    check = cell(r.get("check", ""))
    member = r.get("member", "")
    if member and member != ".":
        check = f"{cell(member)}: {check}"
    message = cell(r.get("message", ""))
    icon = icons.get(status, ":grey_question:")
    print(f"| {icon} {status} | {check} | {message} |")
