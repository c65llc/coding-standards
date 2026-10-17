---
title: "Scripts"
description: "Reference for every automation script in the scripts/ directory."
---

# Scripts

All automation scripts live in the `scripts/` directory. They are written in Bash and require no dependencies beyond standard Unix tools (with optional `gh` and `jq` for GitHub features).

## setup.sh

**Purpose:** First-time setup of coding standards in a project.

**Usage:**

```bash
./scripts/setup.sh [--agents <list>|all|detect] [--languages <list>] [--role <role>] [--workflow] [--dry-run]
./scripts/setup.sh --help
```

Or via Make:

```bash
make setup
```

**What it does:**

1. Detects whether it is running inside the standards repo itself or inside a project that uses it as a submodule.
2. Determines which agents to configure: the ones already present in the project (`--agents detect`, the default) or the explicit list you pass.
3. Assembles each agent's config from the shared content blocks, never clobbering a customized file (see [Safe setup](../getting-started/how-it-works.md)):
   - `CLAUDE.md` (Claude Code), plus `.claude/settings.json` and the `/merge-standards` skill
   - `.cursorrules` and `.cursor/commands/` (Cursor)
   - `.github/copilot-instructions.md` (GitHub Copilot)
   - `.gemini/GEMINI.md` and `.gemini/settings.json` (Gemini CLI)
   - `AGENTS.md` (OpenAI Codex)
   - `.aider-instructions.md` and `.aiderrc` (Aider)
4. Writes `.standards.yml` (declared languages, agents, role) and `.standards-checksums`.
5. In detect mode only: installs a `post-merge` git hook that checks for standards updates and runs `setup-git-aliases.sh` to configure global git aliases.
6. Adds `.cursorrules.backup`, `.standards_tmp/` and `.standards-pending/` to `.gitignore`.

**Flags:**

| Flag | Effect |
| --- | --- |
| `--agents <list>` | Comma-separated agents (`claude-code`, `cursor`, `copilot`, `gemini`, `codex`, `aider`), `all`, or `detect` (default). An explicit list installs **only** that agent's artifacts: no git hooks, git aliases, Cursor commands, `.claude/settings.json` or `.gemini/` unless the owning agent is listed. Unknown agent names exit 2. |
| `--languages <list>` | Comma-separated languages; skips `detect-languages.sh`. |
| `--role <role>` | Role content block to include (default `service`). |
| `--workflow` | Also install the opt-in `standards-review.yml` and `trufflehog.yml` workflow templates. |
| `--dry-run` | Print every write that would happen without modifying anything. |
| `-h`, `--help` | Print usage and exit 0 without touching the project. |

Unknown options print `Unknown option: <flag>` plus the usage text and exit 2 before anything is written.

```bash
# Codex-only project: AGENTS.md + .standards.yml, nothing else
.standards/scripts/setup.sh --agents codex

# Claude Code + Cursor with explicit languages
.standards/scripts/setup.sh --agents claude-code,cursor --languages typescript
```

---

## sync-standards.sh

**Purpose:** Pull the latest standards and update the configuration files for the agents declared in `.standards.yml`.

**Usage (from the project root):**

```bash
./.standards/scripts/sync-standards.sh [--dry-run] [--aliases]
```

Or via Make:

```bash
make sync-standards
```

**Flags:**

| Flag | Effect |
| ---- | ------ |
| `--dry-run` | Print every write that would happen; modify nothing. |
| `--aliases` | Also run `setup-git-aliases.sh`. This changes **global** git config, so it is off by default and never runs as part of a plain project sync. |
| `-h`, `--help` | Show usage. Unknown options exit 2. |

**What it does:**

1. Refuses to run when the project root resolves to `.standards/` (i.e. you ran it from inside the submodule, as the old `make -C .standards sync-standards` wrapper did). Run it from the project root instead.
2. If a `.standards` submodule exists, fetches from the remote and pulls if there are new commits. An unreachable remote is a warning, not a failure — the sync continues from the local checkout.
3. Reads `agents:`, `languages:` and `role:` from `.standards.yml` (falls back to the legacy `.standards-config`, then to all agents + language auto-detection).
4. Re-assembles one config per declared agent (`CLAUDE.md`, `.cursorrules`, `.github/copilot-instructions.md`, `.gemini/GEMINI.md`, `AGENTS.md`, `.aider-instructions.md`). Customized files are staged to `.standards-pending/` instead of being overwritten.
5. Installs agent-specific extras **only for declared agents**: Cursor custom commands (`cursor`), `.gemini/settings.json` (`gemini`, JSON-validated first), `.claude/settings.json` and the `/merge-standards` skill (`claude-code`).
6. Syncs language-specific tool configs for detected languages.
7. Lists available standards files.

---

## diff-standards.sh

**Purpose:** Show what `sync-standards.sh` would change, without modifying anything.

**Usage (from the project root):**

```bash
./.standards/scripts/diff-standards.sh [--exit-code] [project-root]
```

Or via Make:

```bash
make diff-standards
```

**Flags:**

| Flag | Effect |
| ---- | ------ |
| `--exit-code` | Exit 1 when any declared agent's assembled config (`CLAUDE.md`, `AGENTS.md`, `.cursorrules`, …) would change or be created; exit 0 otherwise. The project-specific section is never drift; verbatim-copied auxiliary files (`.aiderrc`, `.gemini/settings.json`, …) are not diffed. Without the flag the script always exits 0. |
| `-h`, `--help` | Show usage. Unknown options exit 2. |

**What it does:**

1. Refuses to run from inside `.standards/` (same guard as `sync-standards.sh`).
2. Assembles each declared agent config to a temp file and prints a unified diff against the installed file (`+ Would create` for missing ones).
3. Prints a summary and, when changes are pending, the exact command to apply them (`./.standards/scripts/sync-standards.sh`).

Use it as a CI gate:

```yaml
- name: Agent configs match the standards
  run: ./.standards/scripts/diff-standards.sh --exit-code
```

---

## setup-git-aliases.sh

**Purpose:** Configure global git aliases and settings based on project conventions.

**Usage:**

```bash
./scripts/setup-git-aliases.sh
```

Called by `setup.sh`, and by `sync-standards.sh` only when you pass `--aliases` (it changes global git config, so a plain project sync never runs it).

**What it configures:**

Git settings:

| Setting | Value | Purpose |
| ------- | ----- | ------- |
| `push.autoSetupRemote` | `true` | Auto-set upstream when pushing new branches |
| `push.default` | `simple` | Push only the current branch |
| `init.defaultBranch` | `main` | Default branch name for new repos |

Key aliases:

| Alias | Command | Description |
| ----- | ------- | ----------- |
| `git co` | `checkout` | Switch branches |
| `git cob` | `checkout -b` | Create and switch to a new branch |
| `git st` | `status` | Show working tree status |
| `git cm` | `commit -m` | Commit with a message |
| `git lg` | `log --oneline --decorate --graph --all` | Visual log graph |
| `git up` | `fetch + rebase origin/main` | Update branch from main |
| `git refresh-main` | (complex) | Reset local main to match origin/main |
| `git feat <name>` | `checkout -b feature/<name>` | Start a feature branch |
| `git fix <name>` | `checkout -b fix/<name>` | Start a fix branch |
| `git pushf` | `push --force-with-lease` | Safe force push |
| `git aliases` | (list all aliases) | Show configured aliases |

The script prompts before overwriting any existing alias that has a different value.

---

## add-copilot-instructions-pr.sh

**Purpose:** Create a pull request that adds GitHub Copilot custom instructions to a repository.

**Usage:**

```bash
./scripts/add-copilot-instructions-pr.sh [base-branch]
```

Or via Make:

```bash
make add-copilot-instructions
```

**What it does:**

1. Checks for GitHub CLI (`gh`).
2. Locates the Copilot instructions source file in the standards repo.
3. Creates a feature branch (`add-copilot-instructions` or `update-copilot-instructions`).
4. Copies `.github/copilot-instructions.md` into the project.
5. Commits and pushes.
6. Opens a pull request via `gh pr create` with a detailed description.

**Prerequisites:** `gh` CLI installed and authenticated.

**Arguments:**

| Argument     | Default | Description                   |
| ------------ | ------- | ----------------------------- |
| `base-branch` | `main` | Branch to target with the PR |

---

## fetch-pr-comments.sh

**Purpose:** Fetch all unresolved comments on a pull request and save them as JSON for AI processing.

**Usage:**

```bash
./scripts/fetch-pr-comments.sh [PR_NUMBER]
```

If no PR number is given, the script looks up the PR associated with the current branch.

**What it does:**

1. Checks for `gh` and `jq`.
2. Fetches PR metadata, unresolved review threads, and general comments in a single API call.
3. Writes structured JSON to `.standards_tmp/pr-comments-<timestamp>.json`.
4. Prints the file path to stdout (for the Cursor `/address_feedback` command to consume).

**Output format:**

```json
{
  "pr": { "number": 42, "url": "...", "title": "...", "state": "OPEN", "author": {...} },
  "reviewThreads": [...],
  "generalComments": [...],
  "summary": {
    "totalUnresolvedThreads": 3,
    "totalUnresolvedComments": 1
  }
}
```

**Prerequisites:** `gh` CLI (authenticated), `jq`.

---

## generate-pr-content.sh

**Purpose:** Gather git information about the current branch for AI-powered PR generation.

**Usage:**

```bash
./scripts/generate-pr-content.sh [base-branch]
```

**What it does:**

1. Collects branch name, commit messages, changed file list, and diff statistics.
2. Writes everything to `.standards_tmp/pr-content-<timestamp>.txt`.
3. Prints the file path to stdout (for the Cursor `/pr` command to consume).

**Arguments:**

| Argument | Default | Description |
|----------|---------|-------------|
| `base-branch` | `main` | Branch to diff against |
