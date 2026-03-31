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

   # Maven Central (via search API)
   curl -s "https://search.maven.org/solrsearch/select?q=g:<group>+AND+a:<artifact>+AND+v:<version>&rows=1&wt=json" | jq -r '.response.docs[0].timestamp'
   ```

4. Calculate the age of each version: `now - publish_date`. Flag any version younger than 72 hours.

5. Report results:
   - **PASS**: "All N dependency versions are older than 72 hours."
   - **FAIL**: List each failing dependency with its name, version, publish date, and age. Example:

     ```text
     FAIL: axios@1.14.1 — published 2026-03-31T00:21Z (4 hours ago). Minimum age: 72 hours.
     ```

## Exception Process

If a dependency fails the age gate but is a critical security patch:

1. Confirm the user has **team lead or security owner approval**
2. Require a **documented justification** in the PR description
3. Note that a **follow-up review within 24 hours** is required
4. Allow the merge with a warning, not a block

Reference: `standards/security/sec-01_security_standards.md` §5 — Dependency Age Gate.

## After Check

Report: "Age gate: N dependencies checked, X passed, Y failed (younger than 72 hours)."
