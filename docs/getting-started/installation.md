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

- Detect which AI agents your project already uses and assemble their configs (`CLAUDE.md`, `.cursorrules`, `AGENTS.md`, ...)
- Write `.standards.yml` and `.standards-checksums`
- Set up a post-merge git hook that checks for standards updates
- Gitignore the agent worktree root (`worktree_dir:` in `.standards.yml`, default `.claude/worktrees`) and install a pre-commit guard that refuses commits adding worktree paths
- Configure git aliases for common workflows

To install for a specific agent only, pass `--agents`. An explicit list installs **only** that agent's artifacts: no git hooks, git aliases, Cursor commands, `.claude/settings.json` or `.gemini/` unless the owning agent is listed. Standards-owned files are still written in every mode: `.standards.yml`, `.standards-checksums`, the `.gitignore` entries, `.trufflehog-ignore`, and any tool configs for detected languages (for example `.eslintrc`, `.ruff.toml`).

```bash
.standards/scripts/setup.sh --agents codex                 # AGENTS.md + standards-owned files
.standards/scripts/setup.sh --agents claude-code,cursor    # two agents
.standards/scripts/setup.sh --help                         # all flags
```

Unknown flags are rejected with exit code 2 before anything is written. See the [scripts reference](../reference/scripts.md) for every flag.

#### Optional: containerized agent-dev environment

The starter kit for [arch-09](../../standards/architecture/arch-09_containerized_agent_dev_standards.md) (a disposable Docker dev container with a deny-by-default egress proxy, where AI agents run with broad permissions) is opt-in, like `--workflow`:

```bash
.standards/scripts/setup.sh --containerized             # add --dry-run to preview
```

This installs `Dockerfile.dev`, `Dockerfile.prod`, `Dockerfile.egress`, `docker-compose.dev.yml`, `scripts/init-workspace.sh`, `scripts/setup-proxy.sh`, the `bootstrap-*.sh` IDE scripts, `proxy/` and `.devcontainer/devcontainer.json`, with the `.example` suffix stripped and the scripts made executable; when Cursor is among the configured agents it also installs `.cursor/rules/containerized-dev.mdc`. `.env` and `.env.secret` are added to `.gitignore` (the P0 guard from arch-09 §5; `init-workspace.sh` refuses to write secrets until they are). Existing files are never overwritten: one that differs from the kit is kept and the kit's version is staged to `.standards-pending/<path>` with a note in `MERGE_PLAN.md`. Without the flag, setup only prints how to install the kit.

Then, on the host: adapt `Dockerfile.dev` and `proxy/project-whitelist.txt`, run `./scripts/init-workspace.sh` and `./scripts/setup-proxy.sh`, bring the stack up with `docker compose -f docker-compose.dev.yml up -d --build`, and run the Definition of Done checks in the [kit README](../../templates/containerized-dev/README.md) — the observed deny-path failure on your host is the only evidence of compliance. The [Containerized Dev Validation](../guides/containerized-dev-validation.md) guide walks through every check with the output to expect and records the run that pinned the kit's versions.

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

If the project already manages its hooks (lefthook, husky, or its own `make hooks`), declare `hooks: lefthook`, `hooks: husky` or `hooks: custom` in `.standards.yml`: setup then leaves the native hook alone and `doctor.sh`'s `Git Hooks` check is satisfied by the declared manager (see [Curated Agent Configs](../guides/customization.md#curated-agent-configs)).

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
# Use the sync script (run from the project root)
./.standards/scripts/sync-standards.sh
# or, if your Makefile has the target
make sync-standards

# Preview first, and fail CI when configs have drifted
./.standards/scripts/diff-standards.sh --exit-code
```

Do not copy `.standards/.cursorrules` over your own `.cursorrules` and do not run the scripts from inside `.standards/` (`make -C .standards ...`): that file is the standards repo's own config, and the scripts refuse to run when the project root resolves to `.standards/`.

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
