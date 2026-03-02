---
title: "Customization"
description: "How to fork, customize, and distribute your own version of the coding standards."
---

# Customization

This repository is designed to be forked and tailored to your team's needs. This guide explains which files to change, how to keep your fork in sync with upstream, and how to distribute customized standards to your projects.

## Forking the Repository

1. Fork the repository on GitHub (or clone it into your own organization).
2. Clone your fork locally:

```bash
git clone https://github.com/<your-org>/coding_standards.git
cd coding_standards
```

3. Add the upstream remote so you can pull future updates:

```bash
git remote add upstream https://github.com/c65llc/coding_standards.git
```

## What to Customize

### Standards Documents

The files under `standards/` are the core of what AI agents reference:

| Path | Purpose |
|------|---------|
| `standards/architecture/` | Architecture patterns (Clean Architecture, SOLID) |
| `standards/languages/` | Language-specific conventions and tooling |
| `standards/process/` | Git workflow, documentation, code review |
| `standards/shared/core-standards.md` | Cross-cutting rules (error handling, testing thresholds) |

Edit these files to match your team's conventions. For example, you might change the required test coverage thresholds in `core-standards.md`, or add a new language file.

### Agent Configuration Templates

Each AI agent has a configuration template in `standards/agents/`:

- `standards/agents/copilot/.github/copilot-instructions.md`
- `standards/agents/aider/.aiderrc`
- `standards/agents/codex/.codexrc`

These templates are what `scripts/setup.sh` copies into your projects. Customize them to reference your modified standards.

### .cursorrules

The `.cursorrules` file at the repository root is copied directly into projects. Update it whenever you add or rename standards files.

### Gemini Configuration

The `.gemini/GEMINI.md` file acts as the system prompt for Gemini CLI. Update the project mission, tech stack, and coding standards sections to reflect your team's practices.

### Cursor Commands

The `.cursor/commands/` directory contains Cursor slash commands (`/pr`, `/review`, `/address_feedback`). You can add new commands or modify existing ones to fit your workflow.

## Keeping Your Fork Updated

Periodically merge changes from the upstream repository:

```bash
# Fetch upstream changes
git fetch upstream

# Merge upstream main into your fork's main
git checkout main
git merge upstream/main

# Resolve any conflicts, then push
git push origin main
```

If you prefer a rebase workflow:

```bash
git fetch upstream
git checkout main
git rebase upstream/main
git push origin main --force-with-lease
```

### Handling Conflicts

Conflicts typically occur in files you have customized. When resolving:

- Keep your customizations where they differ intentionally.
- Accept upstream changes for new features or bug fixes you want.
- Review new standards files that upstream has added and decide whether to adopt them.

## Distributing Standards to Your Team

### As a Submodule

Point your projects at your fork instead of the upstream:

```bash
git submodule add https://github.com/<your-org>/coding_standards.git .standards
.standards/scripts/setup.sh
```

### As a Template Repository

Mark your fork as a GitHub template repository. New projects created from the template automatically include your customized standards.

### Via the Installer

Modify `install.sh` to point at your fork's URL, then share the one-liner with your team:

```bash
curl -fsSL https://raw.githubusercontent.com/<your-org>/coding_standards/main/install.sh | bash
```

## Adding Project-Specific Standards

If a single project needs extra rules beyond what the shared standards cover:

1. Create a file like `standards/languages/15_project_specific.md`.
2. Update `.cursorrules` to reference it.
3. Commit to the project repository (not the standards repo) if the rule only applies to that project.

This keeps the shared standards clean while allowing per-project overrides.

## Tips

- **Start small.** Fork the repo, change only what you need, and expand over time.
- **Document deviations.** If you intentionally diverge from upstream, note the reason in a commit message or in the file itself.
- **Automate sync.** Set up a scheduled GitHub Action to check for upstream updates and open a PR on your fork.
- **Version your fork.** Use git tags so projects can pin to a stable version of your customized standards.
