# .standards.yml Schema Reference

> Declarative project configuration for coding-standards.
> Place `.standards.yml` in the project root. It is **committed to version control**.

## Schema Version

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `version` | integer | **yes** | — | Schema version. Current: `1`. |

The `version` field is required and must be present for the file to be parsed.
Future schema changes will increment this number and include migration notes.

---

## Top-Level Fields

### `languages`

Type: list of strings

Languages used in the project. Controls which language-specific blocks are
injected into assembled agent configs and which tool configs are installed.

**Valid values:**

| Value | Standards block | Notes |
|-------|----------------|-------|
| `python` | `lang-python.md` | |
| `typescript` | `lang-typescript.md` | |
| `javascript` | `lang-javascript.md` | |
| `java` | `lang-java.md` | |
| `kotlin` | `lang-kotlin.md` | |
| `jvm` | `lang-java.md`, `lang-kotlin.md` | Shorthand for both |
| `ruby` | `lang-ruby.md` | |
| `rails` | `lang-rails.md`, `lang-ruby.md` | Includes Ruby automatically |
| `rust` | `lang-rust.md` | |
| `swift` | `lang-swift.md` | |
| `dart` | `lang-dart.md` | |
| `zig` | `lang-zig.md` | |
| `go` | `lang-go.md` | |
| `elixir` | `lang-elixir.md` | |

Auto-detected during `setup.sh` if not specified via `--languages`.

---

### `agents`

Type: list of strings

AI agents to configure. Each agent gets an assembled config file in the project.

**Valid values:**

| Value | Output file | Description |
|-------|------------|-------------|
| `claude-code` | `CLAUDE.md` | Anthropic Claude Code |
| `cursor` | `.cursorrules` | Cursor IDE |
| `copilot` | `.github/copilot-instructions.md` | GitHub Copilot |
| `gemini` | `.gemini/GEMINI.md` | Google Gemini CLI |
| `codex` | `AGENTS.md` | OpenAI Codex |
| `aider` | `.aider-instructions.md` | Aider |

Default: all agents with available base templates.

---

### `role`

Type: string

Project role determines which role-specific standards block is included.

**Valid values:** `service`, `library`, `app`, `data-pipeline`

Default: `service`

---

### `profiles`

Type: list of strings

Optional, cross-cutting standards a project **opts in to**. A third selector
axis beside `languages` and `role`: each declared profile injects one block
under a `## Profiles` heading in every assembled agent config (after the role
block, in declared order), installs the skill bound to it, and enables its lint
checks (`lint-checks/profiles/<profile>/`). Nothing enables a profile but this
key: `make doctor` and `scripts/detect-profiles.sh` only *suggest*.

**Valid values:**

| Value | Block | Standard | Skill | Lint checks |
|-------|-------|----------|-------|-------------|
| `shared-core` | `profile-shared-core.md` | `arch-07` §7–§9 (tenets, platform-shape decision tree, native-shell audit) | `shared-core` | none |
| `ui-surface` | `profile-ui-surface.md` | `arch-11` (ownership per surface class, the native-feel audit, project rulings over the audit) | `ui-surface` | `web-tells` (WARN) |

Default: none. A missing key and `profiles: []` are the same thing.

An unknown value is a usage error: `setup.sh` and `sync-standards.sh` exit 2
before writing anything, naming the valid list; `doctor` reports it as FAIL.
Un-declaring a profile removes its installed skill when the file is still the
one the standards wrote, and leaves an edited copy with a warning.

```yaml
profiles:
  - shared-core
  - ui-surface
```

---

### `coverage`

Type: object

Coverage thresholds enforced by standards.

| Sub-field | Type | Default | Description |
|-----------|------|---------|-------------|
| `minimum` | integer (0-100) | `95` | Overall minimum coverage percentage; applies to any path no scope claims |
| `domain` | integer (0-100) | `100` | Domain layer minimum coverage percentage |
| `scopes` | list of objects | none | Per-path coverage floors (proc-05 § 6). See below. |

#### `coverage.scopes`

Each scope is measured and gated on its own. Validated by
`scripts/lint-checks/common/coverage-config.sh`.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | **yes** | Directory or glob the floor applies to. Must be unique. |
| `layer` | string | no | `domain`, `core`, `application`, `infrastructure`, `inherited`, `native`, `generated` |
| `minimum` | integer (0-100) | **yes** | Floor for this scope. `domain`/`core` scopes MUST be `100`. |
| `reason` | string | when `minimum` < `coverage.minimum` | Why the code cannot be measured and where it is verified instead |

```yaml
coverage:
  minimum: 95
  domain: 100
  scopes:
    - path: src/domain
      layer: domain
      minimum: 100
    - path: vendor/engine
      layer: inherited
      minimum: 0
      reason: Upstream engine vendored verbatim; covered by upstream's suite (#210)
```

---

### `tests`

Type: object

Test governance settings (proc-05).

| Sub-field | Type | Default | Description |
|-----------|------|---------|-------------|
| `quarantine_file` | string | `test-quarantine.json` | Path (relative to the project root) of the flaky-test quarantine registry. Validated by `quarantine-policy`; a declared file that is missing fails closed. |
| `slow_threshold_ms` | integer | `2000` | Fast-tier per-test ceiling in milliseconds; also the slow-test top-N report cutoff. |

---

### `commits`

Type: object

Conventional Commits enforcement (proc-02 § 2). Read by the `conventional-commits` lint module, by `scripts/check-commit-message.sh` (commit-msg hooks and the standards-review PR-title check), and shared through `scripts/lib/conventional-commits.sh` so the three cannot drift.

| Sub-field | Type | Default | Description |
|-----------|------|---------|-------------|
| `window` | integer (≥ 1) | `50` | Inspect the last N non-merge commits. Ignored whenever a range applies (see precedence). |
| `since` | string (git ref) | none | Inspect `<ref>..HEAD` instead of a window. An unknown ref is a `WARN`, not a crash. |
| `scopes` | list of strings | none | Allow-list for scoped commits (`feat(api): …` must use a listed scope); unscoped commits always pass. Inline `[a, b]` and block lists are both accepted. |

Range precedence: `--since` / `--window` flags > `commits.since` > `STANDARDS_COMMITS_SINCE` (the standards-review action sets it to `origin/<pr-base>`) > `commits.window` > default `50`. A range from any source beats a window, so a pinned `window` never widens a PR check to unrelated mainline history.

```yaml
commits:
  window: 50
  # since: origin/main
  scopes: [api, domain, ui]
```

---

### `release`

Type: object

Release hygiene settings (proc-02 § 5). Read by the `changelog-tags` lint module, which asserts every released `## [x.y.z]` changelog heading has a matching git tag.

| Sub-field | Type | Default | Description |
|-----------|------|---------|-------------|
| `changelog` | string | first of `CHANGELOG.md`, `CHANGELOG`, `CHANGES.md`, `HISTORY.md` | Path (relative to the project root) of the Keep-a-Changelog file. A declared file that is missing or empty fails closed. |
| `tag_prefix` | string | none (accept `v<version>` and `<version>`) | Makes one tag prefix authoritative, e.g. `release-` for `release-1.2.3`. An explicitly empty value (`tag_prefix: ""`) accepts bare `1.2.3` tags only. |

```yaml
release:
  changelog: docs/CHANGES.md
  tag_prefix: v
```

---

### `architecture`

Type: string

Architecture enforcement level.

| Value | Description |
|-------|-------------|
| `clean` | Clean Architecture enforced (dependency rule, layer separation) |
| `none` | No architecture constraints |

Default: `clean`

---

### `security`

Type: string

Security strictness level for merge gates.

| Value | Description |
|-------|-------------|
| `strict` | P0 and P1 block merge |
| `moderate` | P0 blocks merge, P1 warns |
| `permissive` | All security issues are warnings only |

Default: `strict`

---

### `lint`

Type: object

Options for `lint-standards.sh` (the compliance linter).

| Sub-field | Type | Default | Description |
|-----------|------|---------|-------------|
| `exclude` | list of strings | `[]` | Project-relative paths the code-quality file-scanning checks (`*/banned-functions`) skip. Each entry is a path prefix (file or directory) or a shell-style glob: `*` matches within a path segment, `**` any run of characters, `**/` zero or more whole segments. **Not applied to `no-secrets`**, which scans every tracked file so the exclude list cannot hide a committed secret. |

```yaml
lint:
  exclude:
    - docs/              # whole directory
    - skills/smoke.sh    # single file
    - fixtures/**        # glob
```

Built-in exclusions (`.git`, `node_modules`, `vendor`, `dist`, `build`,
`target`, `coverage`, `.worktrees`, `.claude/worktrees`, …) and `.gitignore`
always apply to untracked content; `lint.exclude` adds to them for the
`banned-functions` checks. `no-secrets` scans every tracked file regardless.
See `scripts/lint-checks/README.md` for the full list and matching rules.

---

### `project_overview`, `key_commands`

Type: string (literal block `|` or one-line scalar)

The text the assembler writes into `{{PROJECT_OVERVIEW}}` and `{{KEY_COMMANDS}}` in the base agent templates — the `## Project Overview` paragraph and the `## Key Commands` code block of `CLAUDE.md`. Read by `scripts/lib/template-vars.sh` through `assemble-config.sh`, so `setup.sh`, `sync-standards.sh` and `diff-standards.sh` all see the same text.

With both keys declared a re-assembly reproduces a filled-in config byte for byte: its checksum stays stable, `doctor.sh` reports it as matching, and `sync-standards.sh` keeps regenerating it instead of staging a pending copy. Without them the assembler writes `<!-- TODO(standards): -->` markers. When an existing config already has these sections filled in by hand (what the merge skill used to instruct) and the yml lacks them, `setup.sh` and `sync-standards.sh` print the YAML to add; `/merge-standards` writes it for you. Once the keys are in, the next sync notices the assembly matches the installed file and records the baseline.

`key_commands` is written inside the template's ```` ```bash ```` fence, so give it the commands only, one per line.

```yaml
project_overview: |
  Widget service that renders dashboards for the billing team. A Python API
  (`server/`) and a TypeScript front end (`web/`).
key_commands: |
  make test        # run the test suite
  make lint        # lint and format checks
```

---

### `managed`

Type: mapping of config path → boolean

Per-file management. Every assembled agent config is managed by default: `sync-standards.sh` regenerates it when its checksum matches the last assembly and stages a pending copy to `.standards-pending/` when it does not. Declaring a file `false` marks it **curated** — the project owns it:

| Script | Behaviour for a curated file |
|--------|------------------------------|
| `setup.sh`, `sync-standards.sh` | Never regenerated or staged; reported as `curated (managed: false)`. A curated file that does not exist yet is still created once. |
| `doctor.sh` | A checksum mismatch counts as `curated, not drifted` and the `Checksums` check still passes. |
| `diff-standards.sh` | Upstream template changes are still shown (`Curated (managed: false): +N/-M lines ...`) for manual review, counted separately in the summary and **not** as pending changes, so `--exit-code` stays 0. |

Keys are the config's project-relative path or its basename, quoted if YAML needs it; the inline form works too. Values `false`, `no` and `off` (any case) mean curated; anything else means managed.

```yaml
managed:
  CLAUDE.md: false
  .github/copilot-instructions.md: false
# or: managed: { CLAUDE.md: false }
```

Prefer `project_overview` / `key_commands` when the only customisation is the filled-in overview and commands — that keeps the file managed and still updated by sync. Use `managed: false` for a config you maintain by hand end to end.

---

### `hooks`

Type: string

The git hook manager that owns the post-merge standards-sync reminder and the Conventional Commits `commit-msg` hook.

| Value | Meaning |
|-------|---------|
| `standards` (default when absent) | `setup.sh` writes the native `.git/hooks/post-merge`; `doctor.sh` auto-detects `lefthook.yml` / `.husky/` and otherwise checks the native hook. |
| `lefthook` | `doctor.sh` checks the lefthook config (and warns when no `lefthook.yml` exists, even if a `.husky/` directory is present); `setup.sh` does not install the native hook. |
| `husky` | Same for `.husky/` (a stray `lefthook.yml` is ignored). |
| `custom` | The project's own manager (`make hooks`, a pre-commit framework, …). `setup.sh` leaves the native hook alone and `doctor.sh`'s `Git Hooks` check passes without inspecting it. |

An unrecognised value is a `WARN` in `doctor.sh`, which then falls back to detection, and a warning in `setup.sh`, which then installs the native hook as if `hooks:` were absent. `setup.sh` carries `hooks:`, `managed:`, `project_overview:` and `key_commands:` verbatim into the `.standards.yml` it regenerates.

```yaml
hooks: custom
```

---

### `worktree_dir`

Type: string (project-relative path)

The single directory agent worktrees live under (proc-04 § Worktree Hygiene). Default: `.claude/worktrees`.

| Script | Behaviour |
|--------|-----------|
| `setup.sh` | Adds `<worktree_dir>/` to `.gitignore` (once; a parent entry such as `.claude/` also counts) and installs `templates/pre-commit-worktree-guard.example` as `.git/hooks/pre-commit` when no pre-commit hook exists and the standards own the hooks; otherwise prints how to wire the guard into husky / lefthook / the existing hook. Carries the key verbatim into the regenerated `.standards.yml`. |
| `doctor.sh` | `Worktrees` check: passes when the root is gitignored; reports linked worktree count, oldest idle age and total size; warns on nested worktrees, worktrees outside the root, worktrees idle beyond 14 days or whose directory is gone. |
| `worktree-gc.sh` | Reports the root, collects every linked worktree of the repository (inside or outside the root) that is merged, gone or idle, and flags unregistered directories under the root. |
| `lint-standards.sh`, members discovery | The root joins the built-in exclusions, so a non-hidden root (`worktrees/`) is never scanned and a worktree's own `.standards.yml` is never discovered as a member. |
| `assemble-config.sh`, `assemble-skills.sh` | Resolve `{{WORKTREE_DIR}}` in every agent's base template, the `git-workflow` block and the skills to this value, so `CLAUDE.md`, `AGENTS.md`, `.cursorrules` and the rest all name the same root (#194). |

The value must stay inside the project: an absolute path, `~`, or a `..` segment is rejected — `setup.sh`, `doctor.sh` and `worktree-gc.sh` warn and use the default. The pre-commit guard additionally refuses the roots other agents create on their own (`.worktrees`, `.Codex/worktrees`, `.cursor/worktrees`, `.workspaces`).

```yaml
worktree_dir: .claude/worktrees
```

---

## Migration from `.standards-config`

The legacy `.standards-config` file used `KEY=VALUE` format:

```ini
# .standards-config (legacy)
STANDARDS_ROLE=service
STANDARDS_LANGUAGES=python,typescript
STANDARDS_AGENTS=claude-code,cursor,copilot
STANDARDS_VERSION=2.0.0
```

The `read_standards_config` function in `scripts/lib/checksums.sh` reads both
formats automatically. `.standards.yml` takes precedence when both exist.

To migrate manually:

1. Create `.standards.yml` from the template (`templates/standards.yml.example`).
2. Copy values from `.standards-config`:
   - `STANDARDS_ROLE` maps to `role`
   - `STANDARDS_LANGUAGES` (comma-separated) maps to `languages` (YAML list)
   - `STANDARDS_AGENTS` (comma-separated) maps to `agents` (YAML list)
3. Remove `.standards-config` from the project.
4. Remove `.standards-config` from `.gitignore` (it was previously gitignored;
   `.standards.yml` should be committed).

---

## Examples

### Python Service

```yaml
version: 1
languages:
  - python
agents:
  - claude-code
  - cursor
  - copilot
role: service
coverage:
  minimum: 95
  domain: 100
  scopes:
    - path: src/domain
      layer: domain
      minimum: 100
    - path: src/generated
      layer: generated
      minimum: 0
      reason: protobuf stubs regenerated at build time
tests:
  quarantine_file: test-quarantine.json
  slow_threshold_ms: 2000
architecture: clean
security: strict
```

### TypeScript Library

```yaml
version: 1
languages:
  - typescript
agents:
  - claude-code
  - copilot
role: library
coverage:
  minimum: 90
  domain: 100
architecture: none
security: moderate
```

### Go CLI

```yaml
version: 1
languages:
  - go
agents:
  - claude-code
  - codex
role: app
coverage:
  minimum: 80
  domain: 100
architecture: clean
security: moderate
```

### Elixir Phoenix App

```yaml
version: 1
languages:
  - elixir
agents:
  - claude-code
  - cursor
  - gemini
role: app
coverage:
  minimum: 90
  domain: 100
architecture: clean
security: strict
```
