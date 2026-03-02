---
title: "Makefile Targets"
description: "Reference for every Make target available in the coding standards repository."
---

# Makefile Targets

The Makefile at the repository root provides shortcuts for common tasks. Run `make help` to see all targets with descriptions.

## Targets

### `help`

Display all available targets with descriptions.

```bash
make help
```

### `ls`

List all target names (without descriptions), sorted alphabetically.

```bash
make ls
```

### `setup`

Run the setup script to install standards in a project. This copies `.cursorrules`, agent configuration files, Cursor commands, and git hooks into the project root.

```bash
make setup
```

Equivalent to running `./scripts/setup.sh`.

### `sync-standards`

Pull the latest standards from the remote and update all configuration files (`.cursorrules`, `.aiderrc`, `.codexrc`, `.github/copilot-instructions.md`, `.gemini/`). Also syncs Cursor custom commands and checks git aliases.

```bash
make sync-standards
```

Equivalent to running `./scripts/sync-standards.sh`.

### `check-standards`

Check whether the local standards submodule is up to date with the remote. Exits with code 1 if updates are available, making it suitable for CI pipelines.

```bash
make check-standards
```

Example output when standards are current:

```
Standards are up to date
```

Example output when updates are available:

```
Standards are out of date. Run 'make sync-standards'
```

### `update-standards`

Pull the latest commit from the standards remote and copy the updated `.cursorrules` into the project root.

```bash
make update-standards
```

### `setup-agents`

Set up AI agent configuration files without running the full setup. Useful when you want to add agent configs to a project that already has `.cursorrules`.

```bash
make setup-agents
```

### `add-copilot-instructions`

Create a pull request that adds `.github/copilot-instructions.md` to the repository. The script creates a feature branch, commits the file, pushes, and opens a PR via GitHub CLI.

```bash
make add-copilot-instructions
```

Requires GitHub CLI (`gh`) to be installed and authenticated.

### `lint`

Lint all Markdown files using `markdownlint` (if installed).

```bash
make lint
```

### `format`

Format all Markdown files using `prettier` (if installed).

```bash
make format
```

### `test-scripts`

Validate shell script syntax for `setup.sh` and `sync-standards.sh` using `bash -n`.

```bash
make test-scripts
```

## Quick Reference

| Target | Description |
|--------|-------------|
| `help` | Show all targets with descriptions |
| `ls` | List target names |
| `setup` | First-time project setup |
| `sync-standards` | Pull latest and update all configs |
| `check-standards` | Check if standards are current (CI-friendly) |
| `update-standards` | Pull latest submodule commit |
| `setup-agents` | Install agent configs only |
| `add-copilot-instructions` | PR to add Copilot instructions |
| `lint` | Lint Markdown files |
| `format` | Format Markdown files |
| `test-scripts` | Validate script syntax |
