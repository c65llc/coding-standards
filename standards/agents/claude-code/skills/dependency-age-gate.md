---
name: dependency-age-gate
description: Verify all dependency versions are at least 72 hours old to mitigate supply chain attacks
---

# Dependency Age Gate

Check that every 3rd-party dependency version in the project was published at least 72 hours (3 days) ago, per the P1 rule in `sec-01` §5.

## When to Use

- Before merging any PR that modifies a lockfile or dependency manifest
- When adding a new dependency to the project
- When upgrading dependency versions
- As part of a periodic dependency audit

## Workflow

1. Detect the project's languages. Use `.standards.yml` if present, otherwise run:

   ```bash
   .standards/scripts/detect-languages.sh
   ```

2. For each detected language, identify the lockfile and parse added or upgraded dependency versions:

   | Language | Lockfile | Manifest |
   |----------|----------|----------|
   | Python | `uv.lock`, `requirements.txt` | `pyproject.toml` |
   | JavaScript/TypeScript | `package-lock.json`, `pnpm-lock.yaml` | `package.json` |
   | Ruby | `Gemfile.lock` | `Gemfile` |
   | Rust | `Cargo.lock` | `Cargo.toml` |
   | Java/Kotlin | `gradle.lockfile` | `build.gradle`, `pom.xml` |
   | Dart | `pubspec.lock` | `pubspec.yaml` |
   | Swift | `Package.resolved` | `Package.swift` |
   | Zig | `build.zig.zon` | `build.zig.zon` |

   If checking a PR, focus on `git diff` of the lockfile to find only changed versions.

3. Query the registry API for the publish date of each added or upgraded version:

   ```bash
   # npm
   curl -s "https://registry.npmjs.org/<package>" | jq -r '.time["<version>"]'

   # PyPI
   curl -s "https://pypi.org/pypi/<package>/json" | jq -r '.releases["<version>"][0].upload_time'

   # crates.io
   curl -s "https://crates.io/api/v1/crates/<crate>/versions" | jq -r '.versions[] | select(.num=="<version>") | .created_at'

   # RubyGems
   curl -s "https://rubygems.org/api/v1/versions/<gem>.json" | jq -r '.[] | select(.number=="<version>") | .created_at'

   # pub.dev
   curl -s "https://pub.dev/api/packages/<package>" | jq -r '.versions[] | select(.version=="<version>") | .published'

   # Maven Central (via search API) — returns epoch milliseconds, convert to ISO-8601
   curl -s "https://search.maven.org/solrsearch/select?q=g:<group>+AND+a:<artifact>+AND+v:<version>&rows=1&wt=json" | jq -r '.response.docs[0].timestamp / 1000 | todateiso8601'
   ```

4. Normalize all publish dates to a common format (ISO-8601 or seconds since epoch) before computing ages. The examples above return ISO-8601 strings, except Maven Central which returns epoch milliseconds and must be converted (as shown). Calculate the age of each version: `now - publish_date`. Flag any version younger than 72 hours.

5. Report results:
   - **PASS**: "All N dependency versions are older than 72 hours."
   - **FAIL**: List each failing dependency with its name, version, publish date, and age. Example:

     ```text
     FAIL: axios@1.14.1 — published 2026-03-31T00:21Z (4 hours ago). Minimum age: 72 hours.
     ```

## Exception Process

If a dependency fails the age gate but is a critical security patch, the gate
stays red until the audited override path is complete. Do not recommend
merging on a warning, setting `continue-on-error`, or removing the job.

1. The PR body carries a `Dep-age override: <package>@<version> — <advisory>`
   block with an `Approved-by: @handle` line. A version alone is not a
   justification; the advisory or CVE goes in the block.
2. A **listed approver** (the `DEP_AGE_APPROVERS` repository variable: the
   security owner or team leads), who is **not the PR author**, posts a PR
   comment `Dep-age approved: <full head SHA>` and applies the
   `dep-age-override` label. The comment is the approval: it is bound to the
   exact head, so a later push needs a fresh one. The handle in
   `Approved-by:` must be the comment's author. Tell the user who has to do
   this; never post the comment or apply the label on their behalf.
3. The gate re-runs on pushes, label and body edits and goes green only when
   all three parts agree. Merging then opens a `dep-age-follow-up` issue
   from a merge-time workflow, due 24 hours after merge, with the 72-hour
   maturity check as a second checkpoint. Point the user at that issue; it is
   not optional.
4. A red advisory lane is not an override: moving the CVE audit to a nightly
   job does not waive the age gate for the pin that fixes it.

If the repository has no override workflow, report the gate as FAIL and name
the reference implementation; the age gate is P1 and a warning is not a
substitute.

Reference: `standards/security/sec-01_security_standards.md` §5 — Dependency
Age Gate, "Reference implementation: override label + 24 h follow-up".

## After Check

Report: "Age gate: N dependencies checked, X passed, Y failed (younger than 72 hours)."
