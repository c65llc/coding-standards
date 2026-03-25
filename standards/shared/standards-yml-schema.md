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
| `minimum` | integer (0-100) | `95` | Overall minimum coverage percentage |
| `domain` | integer (0-100) | `100` | Domain layer minimum coverage percentage |

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
