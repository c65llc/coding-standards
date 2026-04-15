#!/usr/bin/env python3
"""Format lint-standards.sh JSON output as a Markdown table row per result."""
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

icons = {"PASS": ":white_check_mark:", "WARN": ":warning:", "FAIL": ":x:"}
for r in results:
    status = r.get("status", "")
    check = r.get("check", "")
    message = r.get("message", "").replace("|", "\\|").replace("\n", " ")
    icon = icons.get(status, ":grey_question:")
    print(f"| {icon} {status} | {check} | {message} |")
