---
name: setup-wizard
description: Guided project onboarding — detect languages, generate .standards.yml, scaffold agent configs
---

# Setup Wizard

Guide a user through onboarding their project to coding-standards. Detects the stack, proposes a configuration, and scaffolds everything.

## When to Use

- When a user says "set up standards" or "onboard this project"
- When `.standards.yml` does not exist yet
- When a project has the `.standards/` submodule but hasn't run setup
- When a user asks "how do I get started with coding-standards?"

## Workflow

### Step 1: Detect Languages

Run language detection:

```bash
.standards/scripts/detect-languages.sh
```

This checks for manifest files (package.json, Cargo.toml, pyproject.toml, Gemfile, etc.) and outputs one language key per line. Present the results to the user:

"Detected languages: python, typescript. Does this look right? Any to add or remove?"

### Step 2: Determine Project Role

Ask the user what kind of project this is:

- **service** — Backend API, web server, microservice
- **library** — Reusable package published for others to consume
- **app** — Frontend application, mobile app, desktop app
- **data-pipeline** — ETL, data processing, ML pipeline

Default to `service` if the user is unsure.

### Step 3: Choose Agents

Present the available agents and ask which to configure:

- **claude-code** — Claude Code (generates `CLAUDE.md`)
- **cursor** — Cursor IDE (generates `.cursorrules`)
- **copilot** — GitHub Copilot (generates `.github/copilot-instructions.md`)
- **gemini** — Gemini CLI (generates `.gemini/GEMINI.md`)
- **aider** — Aider (generates `.aider-instructions.md` + `.aiderrc`)
- **codex** — OpenAI Codex (generates `AGENTS.md`)

Default to the agents the user has tooling for (`.standards/scripts/setup.sh --agents detect` finds the ones already present); if unsure, ask rather than assume one agent.

Every declared agent is treated the same way: its config is assembled from the same blocks, its worktree root comes from `worktree_dir:` in `.standards.yml` (default `.claude/worktrees`), and the standards skills reach it in its own shape (`.claude/skills/`, `.cursor/commands/`, `.github/prompts/`, or a `## Skills` index in `AGENTS.md` / `GEMINI.md` / the Aider instructions). Ask where the project keeps agent worktrees if it already has a convention (`.worktrees/`, `.codex/worktrees/`) and set `worktree_dir:` accordingly.

### Step 3b: Offer Profiles

Profiles are optional, cross-cutting standards a project opts in to; nothing enables one but the committed `.standards.yml`. Run the detector and present its suggestions as a question, never as a decision:

```bash
.standards/scripts/detect-profiles.sh
```

- **shared-core** — one logic core (Rust, WASM, FFI) under thin native shells: tenets, a platform-shape decision tree, a native-shell audit, the `shared-core` skill (`arch-07`)
- **ui-surface** — what makes a UI feel like it belongs on its platform: ownership tables per surface class, a tagged audit, the `web-tells` lint check, the `ui-surface` skill (`arch-11`)

"Detection suggests shared-core (uniffi in Cargo.toml). Declare it? Any other profile?" Leave `profiles:` out when the user declines; pass `--profiles <list>` to `setup.sh` when they accept.

### Step 4: Generate .standards.yml

Write the config file:

```yaml
version: 1
languages:
  - python
  - typescript
agents:
  - claude-code
  - cursor
role: service
coverage:
  minimum: 95
  domain: 100
architecture: clean
security: strict
```

Adjust values based on user answers. Show the file to the user for approval before writing.

### Step 5: Run Setup

`setup.sh` does not read `agents:`, `role:` or `languages:` back from the file written in Step 4. Without flags it detects agents from existing agent config files (none on a fresh project, so it would write `agents: []`), defaults the role to `service` and re-detects the languages. Pass the approved selections explicitly, comma-separated, so the configuration setup writes is the one the user approved. Dry-run first:

```bash
.standards/scripts/setup.sh --dry-run --agents claude-code,cursor --role service --languages python,typescript
```

Show the user what will be created. On approval, run the same command without `--dry-run`:

```bash
.standards/scripts/setup.sh --agents claude-code,cursor --role service --languages python,typescript
```

Setup rewrites `.standards.yml` from these flags; confirm afterwards that its `agents:`, `role:` and `languages:` match what the user approved in Step 4.

### Step 6: Verify

Run the health check:

```bash
.standards/scripts/doctor.sh
```

Report the health score and any issues found.

## After Setup

Report: "Project onboarded. Generated .standards.yml, assembled N agent configs, health score: X/Y."

Suggest next steps:

- "Run `make lint-standards` to check current compliance"
- "Commit the generated files"
- "See the standards-audit skill to run a full compliance check"
