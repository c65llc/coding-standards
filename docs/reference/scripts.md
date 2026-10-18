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
./scripts/setup.sh [--agents <list>|all|detect] [--languages <list>] [--role <role>] [--workflow] [--migrate] [--dry-run]
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
4. Writes `.standards.yml` (declared languages, agents, role; a declared `members:` list is preserved) and `.standards-checksums`. In a monorepo the root `.standards.yml` keeps only the root's own languages, detected from the root's own manifests (a non-empty list makes `lint-standards.sh` run language checks against the root; a sub-root that carries other languages is pointed out so it can become a member), while the root agent configs are assembled from the union of the root's and every member's (see [Monorepos: Members](../guides/customization.md#monorepos-members)); a declared member without a `.standards.yml` gets one bootstrapped with the languages detected in it.
5. In detect mode only: installs a `post-merge` git hook that checks for standards updates, installs the pre-commit worktree guard (`templates/pre-commit-worktree-guard.example`, refusing commits that stage a path under the worktree root) when no pre-commit hook exists and `hooks:` names the standards as the hook manager — otherwise prints how to wire it into husky / lefthook / the existing hook — and runs `setup-git-aliases.sh` to configure global git aliases.
6. Adds `.cursorrules.backup`, `.standards_tmp/`, `.standards-pending/` and the worktree root (`worktree_dir:` in `.standards.yml`, default `.claude/worktrees/`) to `.gitignore`.

**Flags:**

| Flag | Effect |
| --- | --- |
| `--agents <list>` | Comma-separated agents (`claude-code`, `cursor`, `copilot`, `gemini`, `codex`, `aider`), `all`, or `detect` (default). An explicit list installs **only** that agent's artifacts: no git hooks, git aliases, Cursor commands, `.claude/settings.json` or `.gemini/` unless the owning agent is listed. Unknown agent names exit 2. |
| `--languages <list>` | Comma-separated languages; skips `detect-languages.sh`. |
| `--role <role>` | Role content block to include (default `service`). |
| `--workflow` | Also install the opt-in `standards-review.yml` and `trufflehog.yml` workflow templates. |
| `--migrate` | Upgrade a pre-1.2 install (see below). Without it, a pre-1.2 shape is only reported, never rewritten. |
| `--dry-run` | Print every write that would happen without modifying anything. |
| `-h`, `--help` | Print usage and exit 0 without touching the project. |

Unknown options print `Unknown option: <flag>` plus the usage text and exit 2 before anything is written. A value-taking option that is missing its value, given an empty `--flag=` form, or followed by another option (`--languages --help`) also exits 2.

**Upgrading a pre-1.2 install (`--migrate`).** A consumer set up before the 1.2 safe-setup has no `.standards-checksums`, agent configs copied from the old hand-rolled templates that cite standards paths renamed in #21 or removed in #40 (`00_project_standards_and_architecture.md`, `03_python_standards.md`, `arch-03_cursor_automation_standards.md`, …), often a `.codexrc` (Codex now reads `AGENTS.md`) and sometimes a legacy `.standards-config`. A plain sync skips every such file as "manually created", so the dead references never go away; `doctor.sh` reports the shape as a single `Migration` finding. `setup.sh --migrate`:

1. Reads a legacy `.standards-config` for `role`, `languages` and `agents` (command-line flags win), seeds `.standards.yml` from it plus detection, and retires it as `.standards-config.pre-standards-setup`.
2. Rewrites every renamed standards reference in `CLAUDE.md`, `.cursorrules`, `.github/copilot-instructions.md`, `.gemini/GEMINI.md`, `AGENTS.md`, `.aider-instructions.md` and `.aiderrc` in place, using [Renamed Files](renamed-files.md) as the map (whatever prefix the config used — `standards/…`, `.standards/standards/…` or a bare file name — is kept). A list item or comment that only cites a removed standard is dropped; a removed standard inside running text is left in place and listed in the merge plan. Each changed file's original is kept as `<file>.pre-standards-setup` (gitignored).
3. In `.aiderrc`, raises the legacy 90%/80% coverage tiers to the 95% floor (`core-standards.md`; domain stays 100%) and drops a `model =` line that pins one of the models the old templates shipped — a project-chosen model stays.
4. Converts `.codexrc` to Markdown `AGENTS.md` (comment markers stripped, headings kept, references rewritten) and keeps the original as `.codexrc.pre-standards-setup`. If an `AGENTS.md` already exists it is not touched: the conversion is staged as `.standards-pending/AGENTS.md.from-codexrc` instead.
5. Runs the normal safe setup: each migrated config is staged beside its freshly assembled version in `.standards-pending/`, `.standards-checksums` is written, and `MERGE_PLAN.md` gains a *Migration* section (what was rewritten, dropped lines, unresolved removed references). The checksum baseline of a staged file is the **staged assembled version**, so `sync-standards.sh` keeps staging a fresh assembly and never overwrites the migrated file until `/merge-standards` adopts or merges it, after which the checksum matches.

`--migrate --dry-run` prints every rewrite and conversion without writing. On a project that is already migrated (checksums present) the flag is a no-op and a normal setup runs.

```bash
# Codex-only project: AGENTS.md plus the standards-owned files
# (.standards.yml, .standards-checksums, .gitignore entries, .trufflehog-ignore,
# detected language tool configs); no hooks, aliases, or other agents' files
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
3. Reads `agents:`, `languages:`, `role:` and `members:` from `.standards.yml` (falls back to the legacy `.standards-config`, then to all agents + language auto-detection). A pre-1.2 install (no checksums, configs citing renamed standards paths, a `.codexrc`) is pointed at `setup.sh --migrate` first, because a sync alone skips those files as manually created. Members (declared, or auto-discovered `*/.standards.yml`) are listed with their languages, and their languages are added to the root's for the assembly step; a declared member that does not exist is a warning, not a failure.
4. Re-assembles one config per declared agent (`CLAUDE.md`, `.cursorrules`, `.github/copilot-instructions.md`, `.gemini/GEMINI.md`, `AGENTS.md`, `.aider-instructions.md`), filling `{{PROJECT_OVERVIEW}}` / `{{KEY_COMMANDS}}` from `project_overview:` / `key_commands:` in `.standards.yml`. Customized files are staged to `.standards-pending/` instead of being overwritten — unless the fresh assembly reproduces the installed file exactly (the project text was persisted since the last run), in which case the checksum baseline is recorded. A file declared `managed: false` is curated: never regenerated or staged, reported as such. When a customized config has a filled-in overview or commands the yml does not persist, the YAML to add is printed (see [Curated Agent Configs](../guides/customization.md#curated-agent-configs)).
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
| `--exit-code` | Exit 1 when any declared agent's assembled config (`CLAUDE.md`, `AGENTS.md`, `.cursorrules`, …) would change or be created; exit 0 otherwise. The project-specific section is never drift (the installed file seeds the assembly, so the section below the `<!-- BEGIN PROJECT-SPECIFIC` marker is carried through, never shown as deleted); a file declared `managed: false` in `.standards.yml` is diffed and labelled `Curated` for manual review but is not a pending change; verbatim-copied auxiliary files (`.aiderrc`, `.gemini/settings.json`, …) are not diffed. Without the flag the script always exits 0. |
| `-h`, `--help` | Show usage. Unknown options exit 2. |

**What it does:**

1. Refuses to run from inside `.standards/` (same guard as `sync-standards.sh`).
2. Assembles each declared agent config to a temp file and prints a unified diff against the installed file (`+ Would create` for missing ones). Members contribute their languages exactly as in `sync-standards.sh`, so the gate below agrees with a sync.
3. Prints a summary and, when changes are pending, the exact command to apply them (`./.standards/scripts/sync-standards.sh`).

Use it as a CI gate:

```yaml
- name: Agent configs match the standards
  run: ./.standards/scripts/diff-standards.sh --exit-code
```

---

## detect-languages.sh

**Purpose:** Detect a project's languages from manifest files. Feeds `setup.sh`, `sync-standards.sh`, `doctor.sh` and `build-claude-settings.sh`.

**Usage:**

```bash
./scripts/detect-languages.sh [--root-only|--subroots-only] [--skip <dir>]... [/path/to/project]
```

Prints one language key per line (`python`, `rust`, `ruby`, `rails`, `javascript`, `typescript`, `jvm`, `java`, `kotlin`, `swift`, `dart`, `zig`, `go`, `elixir`, `cpp`), each at most once, root first. Besides the project root it inspects the conventional monorepo sub-roots `apps/*`, `packages/*`, `crates/*`, `core`, `server`, `web` and `shells/*` for `Cargo.toml`, `tsconfig*.json`, `package.json`, `Package.swift`, `pyproject.toml`, `go.mod`, `mix.exs`, `CMakeLists.txt` and the other manifests, so a Rust core + SwiftUI shell + TypeScript workers repository detects all three instead of `javascript` alone.

`cpp` (lang-14) is detected from `CMakeLists.txt`, a `.clang-format` (or `_clang-format`) file, or C++ sources (`*.cpp`, `*.cc`, `*.cxx`, `*.hpp`, `*.hh`, `*.hxx`) at the root or up to three levels under `src/`, `include/`, `lib/` or `Sources/` — so a Swift package or Android app that carries a C++ engine is detected as `cpp` too and the C ABI rules reach the project that owns the engine.

| Flag | Effect |
| --- | --- |
| `--root-only` | Inspect only the project root. |
| `--subroots-only` | Inspect only the conventional sub-roots, not the root's own manifests, so a language both the root and a sub-root carry is still attributed to the sub-root (used by setup, sync and diff to assemble sub-root languages into the agent configs). |
| `--skip <dir>` | Do not inspect this root-relative sub-root (repeatable). The member-aware scripts pass every declared member so its languages come from its own `.standards.yml`. |

---

## lint-standards.sh

**Purpose:** Standards compliance linter. Module reference, exclusion rules and PR-mode flags: [scripts/lint-checks/README.md](https://github.com/c65llc/coding-standards/blob/main/scripts/lint-checks/README.md).

**Usage:**

```bash
./scripts/lint-standards.sh [--format text|json|sarif] [--since <ref> | --changed] [--timeout <secs>] [--fail-on-timeout] [project-root]
```

In a monorepo the runner iterates the root plus every member (`members:` in `.standards.yml`, or auto-discovered `*/.standards.yml`): repo-wide checks once at the root, project and language checks per member against that member's own config, one aggregated report. Every JSON and SARIF result carries a `member` field (`.` for the root; the SARIF artifact location is the member directory), the JSON object lists `members`, and text output groups results per member. See [Monorepos: Members](../guides/customization.md#monorepos-members).

---

## doctor.sh

**Purpose:** Standards health check — configuration, members, agent configs, checksums, languages, submodule, git hooks, `.aiderrc` drift, Postgres MCP, `.gitignore` entries, worktrees. Exit 1 on any `FAIL`.

```bash
./scripts/doctor.sh
make doctor
```

The `Worktrees` check (proc-04 § Worktree Hygiene) passes when the worktree root (`worktree_dir:`, default `.claude/worktrees`) is gitignored and reports the repository's linked worktrees — count, oldest idle age, total size. It warns on an invalid `worktree_dir:`, a root that is not gitignored, worktrees nested inside another worktree, worktrees outside the root (`.worktrees/`, `.Codex/worktrees/`, …), and worktrees idle for more than 14 days or whose directory is gone, pointing at `make worktree-gc`.

A pre-1.2 install (no `.standards-checksums`, and agent configs citing renamed or removed standards paths, a `.codexrc`, or a legacy `.standards-config` without `.standards.yml`) short-circuits the report: doctor prints one `Migration` finding naming the files and the single fix, `.standards/scripts/setup.sh --migrate`, and exits 1 without running the other checks (each would only restate the same gap). The detection is shared with `setup.sh` and `sync-standards.sh` (`scripts/lib/migrate.sh`, map in [Renamed Files](renamed-files.md)).

The `Languages` check compares what `detect-languages.sh` finds with what `.standards.yml` declares, for the root (member directories skipped) and for each member (`Languages (server)`). It warns about a supported language that is detected but not declared, and about a declared key that has no standards document or lint checks: agent assembly and the linter silently ignore such a key. The `Members` check fails on a declared member whose directory is missing and warns on one without a `.standards.yml`.

The `Checksums` check names the configs modified since their last assembly and treats a file declared `managed: false` in `.standards.yml` as `curated, not drifted` (the check still passes). The `Git Hooks` check honours `hooks:`: `custom` passes outright (the project's own manager owns the hooks), `lefthook` / `husky` pin which manager's config is read (a missing config is a `WARN`), and an unrecognised value warns and falls back to detection. See [Curated Agent Configs](../guides/customization.md#curated-agent-configs).

---

## worktree-gc.sh

**Purpose:** Remove finished agent worktrees, delete their merged branches, prune stale registrations and report what remains with its idle age and size (proc-04 § Worktree Hygiene).

**Usage:**

```bash
./scripts/worktree-gc.sh [--dry-run] [--max-age <days>] [--keep-dirty] [--no-fetch] [--base <ref>] [project-root]
make worktree-gc                 # ARGS="--dry-run" to preview
```

**What it does:**

1. Fetches `origin` with `--prune` (skip with `--no-fetch`) and picks the base branch (`origin/main`, `origin/master`, `main` or `master`; override with `--base`).
2. Classifies every linked worktree of the repository, wherever it lives:
   - **merged** — its HEAD is contained in the base: worktree removed, branch deleted
   - **gone** — its branch tracks an upstream that was deleted (PR merged, remote branch removed): worktree removed, **branch kept** — "gone" alone does not prove the commits landed (a closed PR or unpushed commits look the same), so the report prints the `git branch -D` to run once you know they did
   - **idle** — no commit or checkout activity for more than `--max-age` days (default 14): worktree removed, **branch kept** (the work is unmerged)
   - **prunable** — the directory is already gone: the registration is pruned
   - everything else is kept and listed with its branch, idle age and size
3. Never touches the main checkout, the worktree it runs from (or targets, when given a project root), a locked worktree, or a worktree that still encloses other registered worktrees (removing the parent would delete the children's files; they are reported and the parent is kept until they are gone). Uncommitted changes in a worktree about to be removed are a warning, not a blocker; `--keep-dirty` leaves such worktrees alone.
4. Reports directories under the worktree root that are not registered worktrees, with their size, and leaves them for you to delete.
5. Prints a summary: worktrees removed, disk reclaimed, branches deleted, worktrees kept, warnings (nesting, strays outside the root, dirty removals).

| Flag | Effect |
| --- | --- |
| `--dry-run` | Print what would be removed; change nothing. |
| `--max-age <days>` | Idle threshold (default 14). |
| `--keep-dirty` | Never remove a worktree with uncommitted changes. |
| `--no-fetch` | Judge merged/gone from the local refs only. |
| `--base <ref>` | Branch to judge "merged" against. |
| `-h`, `--help` | Show usage. Unknown options exit 2. |

Exit 0 on success, 1 when a removal failed or the directory is not a git repository, 2 on a usage error. The worktree root is `worktree_dir:` in `.standards.yml` (default `.claude/worktrees`). Tests: `scripts/test-worktree-gc.sh`.

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

## check-commit-message.sh

**Purpose:** Validate a single commit message or PR title against Conventional Commits and the optional `commits.scopes` allow-list in `.standards.yml`.

**Usage:**

```bash
./scripts/check-commit-message.sh --no-exempt "feat(api): add user endpoint" # positional (PR titles)
./scripts/check-commit-message.sh --file .git/COMMIT_EDITMSG              # commit-msg hook form
./scripts/check-commit-message.sh --project-root /path/to/project "fix: x" # read that project's .standards.yml
```

**Exit codes:** `0` valid or exempt (`fixup!`/`squash!`/`amend!` prefixes, merge commits, `git revert` subjects; `--no-exempt` disables the exemptions, which is how the action checks PR titles since a squash-merged title lands verbatim), `1` invalid (with an explanation on stderr; `--quiet` suppresses it), `2` usage error.

**Used by:**

- `templates/husky-commit-msg.example` and `templates/lefthook.yml.example` (commit-msg hooks)
- The PR-title step of the `standards-review` composite action
- Shares its type list and regex with the `conventional-commits` lint module via `scripts/lib/conventional-commits.sh`

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

---

## generate-standards-lists.sh

**Purpose:** Keep the enumerable sections of the repo's agent configs (standards file lists and language-detection maps) in sync with the `standards/` tree, and gate CI on drift.

**Usage:**

```bash
./scripts/generate-standards-lists.sh            # rewrite generated regions in place
./scripts/generate-standards-lists.sh --check    # validate only; exit 1 on drift
./scripts/generate-standards-lists.sh --root <dir> --check
```

Or via Make:

```bash
make generate-standards-lists
make check-agent-configs
```

**What it does:**

1. Finds every file in the repository that carries a generated region delimited by `<!-- BEGIN GENERATED: <id> -->` and `<!-- END GENERATED: <id> -->` (today: `.cursorrules`, `.github/copilot-instructions.md`, `.gemini/GEMINI.md`, `AGENTS.md`, `CLAUDE.md`, `standards/README.md`).
2. Re-renders each region body from the files actually present under `standards/` (`architecture/arch-NN_*.md`, `languages/lang-NN_*.md`, `process/proc-NN_*.md`, `security/sec-NN_*.md`, plus `shared/core-standards.md`). Text outside the sentinels is never touched. Every target is rendered before any is replaced, so one malformed file aborts the run with nothing rewritten. Files are replaced atomically (staged under `.standards_tmp/`, then renamed into place), so a failed write leaves the existing config intact and the script exits non-zero. All temporaries live in `.standards_tmp/` and are removed on exit.
3. Reads optional descriptions and language triggers from `standards/catalog.tsv`; a file with no row still appears, described by its H1 title.

**Region ids:**

| Id | Renders |
| --- | --- |
| `standards-list` | Every standards document grouped by category, with a description |
| `language-detection` | `<file triggers> → <language standard>` for each language standard |

**`--check` mode** emits `PASS` / `WARN` / `FAIL` lines and exits non-zero on any `FAIL`:

- a generated region whose content differs from a fresh render (stale)
- an agent config that does not carry a required generated region exactly once (e.g. the whole `language-detection` block was deleted from `.cursorrules`, or a merge left two copies), or that has been deleted outright, and likewise a deleted `STRUCTURE.md` or `docs/getting-started/project-structure.md`; write mode fails the same preflight and rewrites nothing
- a file in a category directory (other than `README.md`) that does not follow `<prefix>-NN_<name>.md` — such files are never enumerated, so a malformed name would otherwise vanish from every list silently — or two files sharing one `<prefix>-NN` identifier
- an agent config, base template, or structure doc that references a standards file that does not exist — any complete `standards/….md` path must exist at exactly that path with no `.`/`..` components and nothing trailing the `.md` (a misspelt directory, a typo, a traversal, or a `.md.bak`-style suffix fails), while a bare `<prefix>-NN_<name>.md` or `core-standards.md` may live in any category
- an agent config or structure doc (`standards/README.md`, `STRUCTURE.md`, `docs/getting-started/project-structure.md`) that omits a standards file that does exist
- a `catalog.tsv` row pointing at a file that does not exist, two rows for the same path, or a language standard with no triggers column — including when `catalog.tsv` is missing altogether (a non-language standards file without a row is only a `WARN`; its H1 title is used)

The rendering and splicing functions live in `scripts/lib/standards-lists.sh` and can be sourced independently. Tests: `scripts/test-generate-standards-lists.sh`.
