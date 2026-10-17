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

Pull the latest standards from the remote and update the configuration files for the agents declared in `.standards.yml` (`CLAUDE.md`, `.cursorrules`, `AGENTS.md`, `.github/copilot-instructions.md`, `.gemini/`, `.aider-instructions.md`). Agent-specific extras (Cursor commands, Gemini settings, Claude settings/skills) are installed only for declared agents. Git aliases are never changed unless you run the script directly with `--aliases`.

```bash
make sync-standards
```

Equivalent to running `./.standards/scripts/sync-standards.sh` from the project root. Never run it as `make -C .standards sync-standards` — the scripts refuse to run when the project root resolves to `.standards/`.

### `diff-standards`

Show what `sync-standards` would change, as a unified diff per agent config, without modifying anything.

```bash
make diff-standards
```

Equivalent to running `./.standards/scripts/diff-standards.sh`. Add `--exit-code` to the script invocation to exit 1 when any config would change — a drop-in CI gate.

### `check-standards`

Check whether the local standards submodule is up to date with the remote. Exits with code 1 if updates are available, making it suitable for CI pipelines.

```bash
make check-standards
```

Example output when standards are current:

```text
Standards are up to date
```

Example output when updates are available:

```text
Standards are out of date. Run 'make sync-standards'
```

### `update-standards`

Pull the latest commit from the standards remote and re-sync the agent configs by running `./.standards/scripts/sync-standards.sh` from the project root.

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
| ------ | ----------- |
| `help` | Show all targets with descriptions |
| `ls` | List target names |
| `setup` | First-time project setup |
| `sync-standards` | Pull latest and update declared agent configs |
| `diff-standards` | Preview what sync-standards would change (`--exit-code` to gate CI) |
| `check-standards` | Check if standards are current (CI-friendly) |
| `update-standards` | Pull latest submodule commit |
| `setup-agents` | Install agent configs only |
| `add-copilot-instructions` | PR to add Copilot instructions |
| `lint` | Lint Markdown files |
| `format` | Format Markdown files |
| `test-scripts` | Validate script syntax |
