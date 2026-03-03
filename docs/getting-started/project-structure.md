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
│   │   └── arch-03_cursor_automation_standards.md
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
│   │   └── lang-11_ruby_on_rails_standards.md
│   │
│   ├── process/                    # Process and workflow standards
│   │   ├── proc-01_documentation_standards.md
│   │   ├── proc-02_git_version_control_standards.md
│   │   ├── proc-03_code_review_expectations.md
│   │   └── proc-04_agent_workflow_standards.md
│   │
│   ├── shared/                     # Shared standards for all agents
│   │   └── core-standards.md
│   │
│   └── agents/                     # AI agent configuration templates
│       ├── copilot/
│       │   └── .github/
│       │       └── copilot-instructions.md
│       ├── aider/
│       │   └── .aiderrc
│       └── codex/
│           └── .codexrc
│
├── scripts/                        # Automation scripts
│   ├── setup.sh                    # First-time project setup
│   ├── sync-standards.sh           # Pull latest standards
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
| Languages | `standards/languages/` | Python, Java, Kotlin, Swift, Dart, TypeScript, JavaScript, Rust, Zig, Ruby, Ruby on Rails |
| Process | `standards/process/` | Documentation, git workflow, code review, agent workflow |
| Shared | `standards/shared/` | Core standards that apply across all agents |
| Agent configs | `standards/agents/` | Templates for each AI agent |

### Scalability

Adding support for a new language means creating one file in `standards/languages/`. Adding a new AI agent means creating a directory under `standards/agents/` and updating the setup script.

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
