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
