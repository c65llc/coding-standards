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

Default to all agents the user has tooling for, or `[claude-code]` if unsure.

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

Execute the full setup with dry-run first:

```bash
.standards/scripts/setup.sh --dry-run
```

Show the user what will be created. On approval, run without `--dry-run`:

```bash
.standards/scripts/setup.sh
```

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
