---
title: "Project Structure"
description: "How the coding standards repository is organized and why."
---

# Project Structure

This document explains the repository layout so you can find what you need quickly.

## Directory Overview

```text
.
├── .cursorrules                    # Cursor AI configuration
├── .cursor/
│   └── commands/                   # Cursor custom slash commands
│       ├── pr.md                   # /pr — generate a pull request
│       ├── review.md               # /review — code review
│       └── address_feedback.md     # /address_feedback — resolve PR comments
├── .gemini/                        # Gemini CLI configuration
│   ├── GEMINI.md                   # Repository intelligence for AI agents
│   └── settings.json               # Gemini CLI settings
├── Makefile                        # Automation targets
├── README.md                       # Repository overview
│
├── standards/                      # All standards documents
│   ├── architecture/               # Architecture and automation standards
│   │   ├── arch-01_project_standards_and_architecture.md
│   │   ├── arch-02_automation_standards.md
│   │   ├── arch-04_data_versioning_and_migration_standards.md
│   │   ├── arch-05_resilient_architecture_patterns.md
│   │   ├── arch-06_monorepo_workspace_standards.md
│   │   ├── arch-07_cross_platform_shared_core_standards.md
│   │   ├── arch-08_ci_cd_pipeline_standards.md
│   │   ├── arch-09_containerized_agent_dev_standards.md
│   │   ├── arch-10_agent_tools_and_mcp_server_standards.md
│   │   └── arch-11_ui_surface_standards.md
│   │
│   ├── languages/                  # Language-specific standards
│   │   ├── lang-01_python_standards.md
│   │   ├── lang-02_java_standards.md
│   │   ├── lang-03_kotlin_standards.md
│   │   ├── lang-04_swift_standards.md
│   │   ├── lang-05_dart_standards.md
│   │   ├── lang-06_typescript_standards.md
│   │   ├── lang-07_javascript_standards.md
│   │   ├── lang-08_rust_standards.md
│   │   ├── lang-09_zig_standards.md
│   │   ├── lang-10_ruby_standards.md
│   │   ├── lang-11_ruby_on_rails_standards.md
│   │   ├── lang-12_go_standards.md
│   │   ├── lang-13_elixir_standards.md
│   │   └── lang-14_cpp_standards.md
│   │
│   ├── process/                    # Process and workflow standards
│   │   ├── proc-01_documentation_standards.md
│   │   ├── proc-02_git_version_control_standards.md
│   │   ├── proc-03_code_review_expectations.md
│   │   ├── proc-04_agent_workflow_standards.md
│   │   └── proc-05_test_governance.md
│   │
│   ├── security/                   # Security standards (P0-P2 severity model)
│   │   └── sec-01_security_standards.md
│   │
│   ├── shared/                     # Shared standards for all agents
│   │   └── core-standards.md
│   │
│   ├── catalog.tsv                 # Descriptions/triggers for generated standards lists
│   │
│   ├── skills/                     # Agent-neutral runbooks (merge-standards, standards-audit, ...)
│   │                               # emitted per agent by scripts/assemble-skills.sh
│   │
│   └── agents/                     # AI agent configuration templates
│       ├── claude-code/            # → assembled to CLAUDE.md
│       │   └── base-claude-code.md
│       ├── cursor/                 # → assembled to .cursorrules
│       ├── copilot/                # → assembled to .github/copilot-instructions.md
│       ├── gemini/                 # → assembled to .gemini/GEMINI.md
│       │   └── antigravity.md      # Antigravity Mission Isolation appendix (proc-04 §5)
│       ├── aider/                  # → assembled to .aider-instructions.md + .aiderrc
│       └── codex/                  # → assembled to AGENTS.md
│
├── templates/                      # Copy-and-fill templates for consumer projects
│   ├── docs/                       # ADR, spec, plan, design-pass, verification
│   └── *.example                   # Workflow and config templates
│
├── scripts/                        # Automation scripts
│   ├── setup.sh                    # First-time project setup
│   ├── sync-standards.sh           # Pull latest standards
│   ├── assemble-config.sh          # Assemble one agent config (base + blocks + Skills index)
│   ├── assemble-skills.sh          # Emit the skills per agent
│   ├── setup-git-aliases.sh        # Configure git aliases
│   ├── add-copilot-instructions-pr.sh  # PR to add Copilot instructions
│   ├── fetch-pr-comments.sh        # Fetch unresolved PR comments
│   └── generate-pr-content.sh      # Generate PR title and body
│
└── docs/                           # Documentation
    ├── getting-started/
    │   ├── quick-start.md
    │   ├── installation.md
    │   └── project-structure.md    # This file
    ├── guides/
    │   ├── multi-agent-setup.md
    │   ├── ci-cd-integration.md
    │   ├── customization.md
    │   └── cursor-commands.md
    ├── reference/
    │   ├── makefile-targets.md
    │   ├── scripts.md
    │   └── agent-configs.md
    ├── changelog.md
    └── plans/                      # Internal planning documents
```

## Design Principles

### Logical Grouping

Standards are organized by category so you only look at what applies:

| Category | Path | Content |
| -------- | ---- | ------- |
| Architecture | `standards/architecture/` | Clean Architecture, automation, Cursor integration |
| Languages | `standards/languages/` | Python, Java, Kotlin, Swift, Dart, TypeScript, JavaScript, Rust, Zig, Ruby, Ruby on Rails, Go, Elixir, C++ |
| Process | `standards/process/` | Documentation, git workflow, code review, agent workflow |
| Security | `standards/security/` | Security guidelines with P0-P2 severity model |
| Shared | `standards/shared/` | Core standards that apply across all agents |
| Agent configs | `standards/agents/` | Templates for each AI agent |

### Scalability

Adding support for a new language means creating one file in `standards/languages/` and running `make generate-standards-lists`, which rewrites the standards lists inside every agent config from the tree (CI fails on drift). Adding a new AI agent means creating a directory under `standards/agents/` and updating the setup script.

### Separation of Concerns

- **Standards** live in `standards/` and describe _what_ to do.
- **Scripts** live in `scripts/` and handle _how_ to automate it.
- **Docs** live in `docs/` and explain _why_ and _how to get started_.

## Path References

The `.cursorrules` file and all agent configs reference standards using paths relative to the repository root, for example:

- `standards/architecture/arch-01_project_standards_and_architecture.md`
- `standards/languages/lang-01_python_standards.md`
- `standards/shared/core-standards.md`

Scripts in `scripts/` auto-detect whether they are running inside the standards repo or inside a project that uses it as a submodule, and adjust paths accordingly.
