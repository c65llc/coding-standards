---
title: "Installation"
description: "Detailed guide for installing and configuring coding standards in your project."
---

# Installation

This guide covers every installation method, team onboarding, and ongoing maintenance.

## Installation Methods

### Option 1: Git Submodule (Recommended for Teams)

Best when multiple projects share the same standards.

#### Add the submodule

```bash
git submodule add https://github.com/c65llc/coding-standards.git .standards
git submodule update --init --recursive
```

#### Run setup

```bash
.standards/scripts/setup.sh
```

The setup script will:

- Copy `.cursorrules` to your project root
- Install configuration files for all supported AI agents
- Set up a post-merge git hook that checks for standards updates
- Configure git aliases for common workflows

#### Commit the changes

```bash
git add .cursorrules .gitmodules .github/ .aiderrc .codexrc .gemini/
git commit -m "chore: add project standards submodule"
```

### Option 2: Direct Clone (Single Project)

Best for individual projects or full local control.

```bash
git clone https://github.com/c65llc/coding-standards.git .standards
.standards/scripts/setup.sh
```

### Option 3: Symlink (Local Development)

Best when you maintain a single copy of standards on your machine.

```bash
ln -s /path/to/standards/.cursorrules .cursorrules
```

## Onboarding New Team Members

When someone clones a project that uses submodule-based standards:

```bash
# Clone with submodules included
git clone --recurse-submodules <project-url>

# Or initialize after cloning
git clone <project-url>
git submodule update --init --recursive

# Run setup
.standards/scripts/setup.sh
```

Restart the editor after setup to load the new configuration.

## Updating Standards

### Manual Sync

```bash
make sync-standards
# or
.standards/scripts/sync-standards.sh
```

This pulls the latest standards, updates all AI agent configuration files, and notifies you to restart your editor.

### Automatic Detection via Git Hooks

The setup script installs a `post-merge` hook. After every `git pull` or `git merge`, the hook checks whether the standards submodule has newer commits on the remote and prints a reminder if so.

### CI/CD Validation

Add a check to your pipeline so pull requests fail when standards are out of date:

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

### Scheduled Updates

Optionally auto-update on a schedule:

```yaml
# .github/workflows/update-standards.yml
name: Update Standards

on:
  schedule:
    - cron: '0 0 * * 1'  # Weekly on Monday
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

## Versioning Standards

Tag releases so projects can pin to a known-good version:

```bash
# In the standards repo
git tag -a v1.0.0 -m "Initial standards release"
git push origin v1.0.0
```

Pin a project to a specific version:

```bash
cd .standards
git checkout v1.0.0
cd ..
git add .standards
git commit -m "chore: pin standards to v1.0.0"
```

## Troubleshooting

### Editor Not Loading Rules

1. Confirm the config file (`.cursorrules`, `.github/copilot-instructions.md`, etc.) exists in the project root.
2. Restart the editor completely (quit and reopen).
3. Check file permissions: `chmod 644 .cursorrules`.

### Standards Out of Sync

```bash
# Use the sync script
make sync-standards

# Or update the submodule manually
cd .standards && git pull origin main && cd ..
cp .standards/.cursorrules .cursorrules
```

### Submodule Shows Modified or Detached HEAD

```bash
git submodule status

# Fix detached HEAD
cd .standards
git checkout main
cd ..

# Update submodule reference
git add .standards
git commit -m "chore: update standards submodule"
```
