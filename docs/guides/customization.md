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
git clone https://github.com/<your-org>/coding-standards.git
cd coding-standards
```

1. Add the upstream remote so you can pull future updates:

```bash
git remote add upstream https://github.com/c65llc/coding-standards.git
```

## What to Customize

### Standards Documents

The files under `standards/` are the core of what AI agents reference:

| Path | Purpose |
| ---- | ------- |
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

The `.cursorrules` file at the repository root is the standards repo's own Cursor config. Its standards list and language-detection map are generated from the `standards/` tree: after adding or renaming standards files, add a row to `standards/catalog.tsv` and run `make generate-standards-lists` rather than editing the list by hand. The same applies to `.github/copilot-instructions.md`, `.gemini/GEMINI.md`, `AGENTS.md`, `CLAUDE.md`, and `standards/README.md`.

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
git submodule add https://github.com/<your-org>/coding-standards.git .standards
.standards/scripts/setup.sh
```

### As a Template Repository

Mark your fork as a GitHub template repository. New projects created from the template automatically include your customized standards.

### Via the Installer

Modify `install.sh` to point at your fork's URL, then share the one-liner with your team:

```bash
curl -fsSL https://raw.githubusercontent.com/<your-org>/coding-standards/main/install.sh | bash
```

## Adding Project-Specific Standards

If a single project needs extra rules beyond what the shared standards cover:

1. Create a file like `standards/languages/lang-99_project_specific.md` in the project repository.
2. Add a reference to it by hand in each agent config the project uses (`CLAUDE.md`, `.cursorrules`, `.github/copilot-instructions.md`, and so on), **below the `<!-- BEGIN PROJECT-SPECIFIC -->` marker** at the end of the assembled file. Everything below that marker is preserved verbatim by `make sync-standards`; anything inserted above it changes the assembler-controlled checksum, so later syncs would treat the whole config as customized and stage updates to `.standards-pending/` instead of applying them. (The generator, `make generate-standards-lists`, only runs inside the standards repository and only enumerates its own `standards/` tree, so it neither sees nor lists project-local files.)
3. Commit to the project repository, not the standards repo.

If the rule belongs in the shared standards instead, add the file to the standards repository (or your fork), give it a row in `standards/catalog.tsv`, run `make generate-standards-lists` there, and let `make sync-standards` carry the updated lists to consuming projects.

This keeps the shared standards clean while allowing per-project overrides.

## Curated Agent Configs

Three `.standards.yml` keys give hand-maintained agent configs a first-class representation, so filling in the template no longer trips the checksum and a project that manages its own hooks no longer fails `doctor` (the schema reference, `standards/shared/standards-yml-schema.md`, lists every option).

**Persist the overview and commands.** The base `CLAUDE.md` template has a `## Project Overview` paragraph and a `## Key Commands` block. Filling them in directly in the file changes the assembler-controlled section, so every later sync stages the file to `.standards-pending/` and `doctor` reports it as modified forever. Declare the text instead and the assembler reproduces it on every run:

```yaml
project_overview: |
  Widget service that renders dashboards for the billing team.
key_commands: |
  make test        # run the test suite
  make lint        # lint and format checks
```

If a config already has these sections filled in and the yml lacks them, `setup.sh` and `sync-standards.sh` print exactly this YAML for you to paste (`/merge-standards` writes it); the next sync then records the file as current instead of staging a pending copy identical to it.

**Declare a file curated.** A config you maintain end to end — repo-specific guidance that a regenerate would flatten — is declared with `managed:`:

```yaml
managed:
  CLAUDE.md: false
```

`setup.sh` and `sync-standards.sh` never regenerate or stage a curated file, `doctor.sh` reports a checksum mismatch on it as `curated, not drifted` (the check still passes), and `diff-standards.sh` keeps showing the upstream template changes for manual review without counting them as pending (`--exit-code` stays 0). Everything below the `<!-- BEGIN PROJECT-SPECIFIC` marker is preserved for managed files too, so prefer that section, or `project_overview` / `key_commands`, whenever the customisation fits there — a managed file keeps receiving standards updates, a curated one does not.

**Name your hook manager.** `doctor.sh` fails when no post-merge standards-sync hook is installed. With lefthook or husky it reads their config; for a project that wires hooks itself (`make hooks`, a pre-commit framework), declare it:

```yaml
hooks: custom        # or: lefthook | husky | standards (default)
```

`setup.sh` then leaves the native `.git/hooks/post-merge` alone and the `Git Hooks` check passes. `lefthook` / `husky` pin the manager `doctor` checks (and warn when its config file is missing). `setup.sh` carries all four keys verbatim into the `.standards.yml` it regenerates.

## Worktree Root

Agents work in git worktrees (proc-04), and worktrees sprawl: a survey of four consumer projects found 17 of them under one checkout, 37 GB under another, worktrees nested two deep, and one committed as a submodule. The standard is **one gitignored worktree root per repository**, declared in `.standards.yml`:

```yaml
worktree_dir: .claude/worktrees     # the default; project-relative, never absolute or ..
```

What the tooling does with it:

- **`setup.sh`** adds `<worktree_dir>/` to `.gitignore` (once) and installs the pre-commit guard from `templates/pre-commit-worktree-guard.example` as `.git/hooks/pre-commit` when no pre-commit hook exists and the standards own the hooks. The guard refuses any commit that stages a path under the root — or under the roots other agents create on their own (`.worktrees`, `.Codex/worktrees`, `.cursor/worktrees`). With `hooks: husky` / `hooks: lefthook` / an existing hook, setup prints how to wire the guard in instead (the lefthook template already carries a `pre-commit` block for it).
- **`make doctor`** reports the linked worktrees (count, oldest idle age, total size) and warns on a root that is not gitignored, worktrees nested inside another worktree, strays outside the root, and worktrees idle past 14 days.
- **`make worktree-gc`** (`scripts/worktree-gc.sh`) removes worktrees whose branch is merged (and deletes those branches) or whose upstream is gone (keeping the branch, since "gone" alone does not prove the commits landed), removes worktrees idle for more than 14 days (keeping their unmerged branch), prunes registrations whose directory vanished, and reports the rest. Uncommitted changes are a warning, not a blocker (`--keep-dirty` to opt out); `--dry-run` previews. In a consumer project: `./.standards/scripts/worktree-gc.sh`.
- **`lint-standards.sh`** and member auto-discovery skip the root, so a non-hidden root (`worktrees/`) is never scanned and a worktree's own `.standards.yml` is never mistaken for a member.

Keep build caches outside the worktrees (`CARGO_TARGET_DIR`, the pnpm store, SwiftPM scratch, Gradle, turbo under `~/.cache/<repo>` or `$TMPDIR`) so N worktrees do not mean N copies of `target/` — proc-04 § Worktree Hygiene has the table.

## Monorepos: Members

Most real projects are monorepos: a Rust core with a SwiftUI shell and TypeScript workers, or `server/` + `web/` with the test directory, `mypy` and `eslint` configuration each one level down. Run against the root alone, the scripts assume a single project and report those layouts as missing. `.standards.yml` therefore supports **members** — sub-roots that are projects in their own right, each with its own `.standards.yml`:

```yaml
# .standards.yml (repository root)
version: 1
languages: []          # nothing lives at the root itself
agents: [claude-code, cursor]
members:
  - server
  - web
  - shells/apple
```

```yaml
# server/.standards.yml
version: 1
languages: [python]
lint:
  exclude: [migrations/]
```

Paths are relative to the root config; absolute paths and `..` are rejected. A declared path is also resolved physically: a symlink anywhere in it, or a real location outside the project root, is rejected and reported (`lint-standards.sh` records a `WARN` under the `members` check, `doctor.sh` a `FAIL`), because the root config is PR-controlled and a committed symlink must not let the scripts read or write outside the checkout. Members are not recursive (a member's own `members:` key is ignored).

**Auto-discovery.** Without a `members:` key, every `*/.standards.yml` and `*/*/.standards.yml` one or two levels below the root is a member. Hidden directories (`.git`, `.standards`, `.worktrees`, `.claude/worktrees`, …), `node_modules`, `vendor`, `third_party`, `dist`, `build`, `target` and `coverage` are never entered. Declare `members:` to pin the list (new sub-roots then need an entry), or `members: []` to turn discovery off for a single-root project.

**What each script does with members:**

| Script | Behaviour |
| --- | --- |
| `lint-standards.sh` | Repo-wide checks (`conventional-commits`, `ci-workflow-hygiene`, `headless-ci`, `no-secrets`, `doc-lint`, `changelog-tags`) run once at the root. Project checks (`coverage-config`, `quarantine-policy`, `test-directory-structure`) and the language checks run in every member against that member's own config and `lint.exclude`; they also run at the root unless the root declares no languages (a pure aggregator), and every member (the root included) skips the subtrees of the members nested below it, so a member's file is judged once, under its own config (repo-wide checks still see the whole tree). One aggregated report; every JSON/SARIF result carries a `member` field (`.` for the root), text output groups results per member, and `--since`/`--changed` scopes are re-based onto each member. A declared member that is missing, or has no `.standards.yml`, is a `WARN` finding under the `members` check. |
| `doctor.sh` | Reports the members (`Members` line; a missing declared member is a `FAIL`, one without a config a `WARN`) and runs the languages check for the root (its own manifests only) and for each member (`Languages (server)`). The root is not asked to declare a member's or a sub-root's languages, and a declared key with no standards document or lint checks is flagged as unsupported. |
| `detect-languages.sh` | Also walks `apps/*`, `packages/*`, `crates/*`, `core`, `server`, `web` and `shells/*` for manifests, so a Rust core + Swift shell + TypeScript workers repository detects all three. `--skip <dir>` leaves a member to its own config; `--root-only` disables the walk; `--subroots-only` inspects only the sub-roots (how setup, sync and diff attribute a language to a sub-root even when the root carries it too). |
| `setup.sh` | Resolves the members before rewriting the root config, keeps a declared `members:` list verbatim, writes only the root's own languages (detected from the root's own manifests with `--root-only`, or `--languages`) to the root `.standards.yml` and prints a hint when a conventional sub-root (`apps/*`, `packages/*`, …) carries a language the root does not, so it can be made a member, assembles the root agent configs from the **union** of the root's and the members' languages (the root file is the only one Cursor, Copilot and Aider read; a member with a config contributes exactly what it declares, so `languages: []` contributes nothing, and a member without a config contributes what is detected in it), and bootstraps a `.standards.yml` for a declared member that has none (an existing member config is never rewritten). |
| `sync-standards.sh`, `diff-standards.sh` | Build the same union for the root assembly — the root's declared languages (else its own manifests), the conventional sub-roots that are not members, and every member — so `diff-standards.sh --exit-code` agrees with sync and with a fresh setup. |
| `standards-review` action | Posts the aggregated report; a member's checks are prefixed with its path (`server: python/banned-functions`). |

Running `lint-standards.sh server` directly still treats `server/` as a single-root project, so a per-member Makefile target keeps working; the root run simply makes it unnecessary.

## Tips

- **Start small.** Fork the repo, change only what you need, and expand over time.
- **Document deviations.** If you intentionally diverge from upstream, note the reason in a commit message or in the file itself.
- **Automate sync.** Set up a scheduled GitHub Action to check for upstream updates and open a PR on your fork.
- **Version your fork.** Use git tags so projects can pin to a stable version of your customized standards.
