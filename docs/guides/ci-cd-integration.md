---
title: "CI/CD Integration"
description: "Automate standards enforcement in your CI/CD pipeline."
---

# CI/CD Integration

This guide shows how to integrate coding standards into your continuous integration and deployment workflow so that standards drift is caught automatically.

## How Standards Stay Current

Three layers keep your project in sync:

1. **Git hooks** -- detect updates after every pull or merge.
2. **Sync scripts** -- manually or programmatically update all agent configs.
3. **CI/CD checks** -- block pull requests when standards are out of date.

## Standards Check in CI

Add a job that fails when the standards submodule is behind the remote:

```yaml
# .github/workflows/standards-check.yml
name: Check Standards

on: [push, pull_request]

jobs:
  check-standards:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: true

      - name: Check standards are up to date
        run: make check-standards
```

`make check-standards` compares the local submodule commit with `origin/main`. If they differ, the step exits with a non-zero code and the workflow fails.

## Scheduled Auto-Update

Create a workflow that opens a commit (or a pull request) when new standards are available:

```yaml
# .github/workflows/update-standards.yml
name: Update Standards

on:
  schedule:
    - cron: '0 0 * * 1'  # Every Monday at midnight UTC
  workflow_dispatch:

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: true

      - name: Update standards submodule
        run: |
          cd .standards
          git pull origin main
          cd ..
          git add .standards
          git commit -m "chore: update standards submodule" || exit 0
          git push
```

## Git Hooks

The `scripts/setup.sh` script installs a `post-merge` hook that runs after every `git pull` or `git merge`. The hook fetches from the standards remote and prints a warning if newer commits exist.

```bash
# Installed at .git/hooks/post-merge
#!/bin/bash
if [ -d ".standards" ]; then
    cd .standards
    git fetch origin >/dev/null 2>&1
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null)
    if [ "$LOCAL" != "$REMOTE" ] && [ -n "$REMOTE" ]; then
        echo "Standards repository has updates. Run: make sync-standards"
    fi
fi
```

## Manual Sync

Run the sync script at any time to pull the latest standards and update all agent configuration files:

```bash
make sync-standards
# or
.standards/scripts/sync-standards.sh
```

After syncing, restart your editor to pick up the new configuration.

## Update Flow

```text
Standards Repository (new commit pushed)
         |
         v
Project Repositories
         |
         +-- Git hook detects update --> prints reminder
         +-- CI/CD job checks --> fails PR if outdated
         +-- Manual sync --> make sync-standards
         +-- Scheduled workflow --> auto-updates weekly
         |
         v
Agent config files updated (.cursorrules, .aiderrc, etc.)
         |
         v
Restart editor --> new rules active
```

## Best Practices

- **Check on every PR.** A failing standards check is the easiest way to prevent drift.
- **Pin to versions** in production projects. Use `git checkout v1.x.x` inside the submodule so updates are intentional.
- **Automate notifications.** Post in Slack or Discord when the scheduled update workflow pushes a new commit.
- **Test first.** Try new standards in a test project before rolling them out to all repositories.
