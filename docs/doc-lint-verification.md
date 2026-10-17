# doc-lint and Documentation Templates — Verification

- **Status:** Historical (point-in-time record; do not edit after the PR merges)
- **Date:** 2026-10-17
- **PR:** #208
- **Related:** #196, [proc-01 §1, §9, §11](../standards/process/proc-01_documentation_standards.md), [proc-05 §7](../standards/process/proc-05_test_governance.md)
- **Commit verified:** the PR #208 head at merge. CI run `39050423792` verified `eb37b4f`; every later push re-ran the same lanes (ShellCheck, Test Scripts, Markdown Lint, Build Website, Lint Standards dogfood, CI Gate) and the PR's check list is the record for the final commit.

A verification doc records what was actually proven before merge — not what
the plan intended. A green pipeline is evidence, not proof; this document says
what the evidence covers and, just as importantly, what it does not.

## Summary

PR #208 ships the `doc-lint` compliance module (ADR required fields plus
relative-link resolution, with a CommonMark-aware scanner, a built-in
self-test and fail-closed empty scans), the five document templates under
`templates/docs/`, the `docs/README.md` index, and the known-traps,
stale-response and error-copy rules in the standards. It was verified by the
repository's functional suites on macOS and Ubuntu, by ShellCheck and
markdownlint, and by running `doc-lint` against this repository itself. The
residual risk is a CommonMark construct the scanner does not model producing
a false FAIL in a consumer's CI; the FAIL line names the file and target, and
the fix is to fence the example or correct the link.

## Tests run

| Suite | Command | Where | Result |
|-------|---------|-------|--------|
| lint-standards functional (includes doc-lint Tests 25–56, 32 tests) | `./scripts/test-lint-standards.sh` | local (macOS 15, bash 3.2, awk 20200816) and CI (ubuntu-latest, run 39050423792 and later runs) | 201 passed, 0 failed |
| Safe-setup functional (exercises `assemble-config.sh`, which now seeds the Known Traps table) | `./scripts/test-setup-safe.sh` | local and CI | 47 passed, 0 failed |
| Bootstrap functional | `./scripts/test-bootstrap.sh` | local and CI | 30 passed, 0 failed |
| format-results.py | `make test-scripts` | local and CI | 10 passed, 0 failed |
| gh-task CLI | `./scripts/test-gh-task.sh` | local and CI | all passed (the suite prints pass/fail only, not a count) |
| ShellCheck | `shellcheck -x --severity=warning scripts/*.sh scripts/lib/*.sh scripts/lint-checks/*/*.sh bin/gh-task install.sh website/scripts/*.sh` | local and CI | clean |
| Markdown lint | `markdownlint 'standards/**/*.md' 'docs/**/*.md' '*.md' --ignore REVIEW.md` | local and CI | clean |
| Dogfood | `./scripts/lint-checks/common/doc-lint.sh .` | local and CI (Lint Standards lane) | PASS — 138 Markdown files checked, 1 ADR complete, all relative links resolve |
| Dogfood (enforcing) | `ci-workflow-hygiene.sh .` and `headless-ci.sh .` | local and CI | PASS, PASS |
| Website build | `cd website && npm ci && npm run build` | CI (Build Website lane) | success |

**Total:** 288 counted tests run (201 + 47 + 30 + 10), 288 passed, 0 failed, 0 skipped — plus the gh-task suite, which reports pass/fail only.

## Coverage per module

This repository is a standards library of bash scripts and Markdown; it has no
coverage tooling and declares no `coverage.scopes` in `.standards.yml`, so
there is no numeric floor to report against. Coverage of `doc-lint` is
behavioural: every rule stated in the script header has at least one
functional test that trips it and one that passes, plus the built-in
self-test fixtures that run on every invocation.

| Module | Lines | Branches | Target (scope floor) | Notes |
|--------|-------|----------|----------------------|-------|
| `scripts/lint-checks/common/doc-lint.sh` | n/a | n/a | n/a — no coverage tool for bash in this repo | 32 functional tests (Tests 25–56 in `test-lint-standards.sh`) plus the self-test fixtures: ADR fields and vocabulary, calendar dates, template exemption, fenced/indented/quoted code (including quoted and commented ADR examples), list nesting, code spans across lines and unmatched backticks, HTML comments (including a fence opener inside one), escapes, entities, percent-encoding, titles, footnotes, non-ASCII, mixed-case and newline-containing filenames, links that climb above the project root, the `--since/--changed` file scope, empty scan |
| `scripts/assemble-config.sh` (Known Traps seed) | n/a | n/a | n/a | Exercised by `test-setup-safe.sh` (47 tests) in fixture projects |

## Manually verified

- Dogfood on this repository — macOS 15, bash 3.2, awk 20200816, UTF-8 locale — the author: `doc-lint` reports PASS over 138 Markdown files including the templates, the new index and this document.
- Self-test tripping — macOS — the author: during development the self-test caught a real defect before any fixture-based test ran. The first version of the title parser used `close` as an awk local variable; `close` is an awk built-in, the program failed to compile, and the module printed `FAIL doc-lint self-test failed (detector rot, refusing to report): link fixture extracted '' …` and exited 1 instead of reporting zero links. After the rename the self-test passed.
- Multibyte handling — macOS — the author: before `LC_ALL=C`, a fixture containing `ü` aborted macOS awk with `multibyte conversion failure` and every link in that file was silently skipped; Test 35 (non-ASCII filename with a broken link) failed, then passed after the fix.
- Ubuntu parity — CI: the Test Scripts lane ran the same 201-test suite on ubuntu-latest for each push.

## What was NOT verified

- Windows / Git Bash and BusyBox or `gawk --posix` awk: CI runs ubuntu-latest, local runs are macOS. The scanner relies only on POSIX awk features, but no run on those platforms exists.
- Installation into a real consumer repository: `setup.sh` and `assemble-config.sh` (including the seeded Known Traps table) were exercised only against fixture projects in `test-setup-safe.sh`, not against a live project with an existing PROJECT-SPECIFIC section.
- Performance on large documentation trees: `doc-lint` spawns an awk process per file (two for ADRs); no measurement exists above the 138 files in this repository. Tracked as a follow-up if a consumer reports slow runs.
- CommonMark constructs the scanner does not model: HTML blocks other than comments, link reference definitions and inline links that span lines, setext (underlined) headings for ADR sections, link destinations containing unbalanced parentheses, and lazy continuation lines inside nested block quotes. Each would produce either a false FAIL (named in the output) or a missed link.
- Symbolic links: the root-escape check is lexical (`..` normalisation), so a tracked symlink pointing outside the project is not detected; `lint-files.sh` already drops symlinked Markdown files from the candidate list.
- The website build was verified by CI only; the synced content was not inspected by hand.

## Residual risk

- A consumer document uses a construct the scanner mis-parses and CI reports a false broken link — detection: the FAIL line names the file and the extracted target, so the mismatch is visible at a glance — mitigation: fence the example or fix the link; parser fixes ship with the next `sync-standards`.
- A real broken link sits inside an unmodelled construct and is not reported — detection: readers and the website build's own link handling — mitigation: `markdownlint` and the website build remain independent gates; `doc-lint` is additive.
- The fail-closed empty scan trips in a consumer that genuinely has no Markdown — detection: the FAIL names the pathspec and the working directory — mitigation: add the README that core-standards already requires; this is the intended behaviour under proc-05 §7.2.
