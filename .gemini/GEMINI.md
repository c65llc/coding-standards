# Repository Intelligence & Standards

## 🎯 Project Mission

This repository provides comprehensive development standards and guidelines for software projects, designed to work seamlessly with AI coding assistants including Cursor AI, GitHub Copilot, Claude Code (Aider), OpenAI Codex, Gemini CLI, and Google Antigravity.

The standards cover architecture patterns, language-specific conventions, process workflows, and automation requirements to ensure consistent, maintainable code across teams and projects.

## 🛠 Tech Stack & Constraints

- **Runtime:** Shell scripts (bash), Makefile automation
- **Documentation:** Markdown-based standards and guides
- **Version Control:** Git with Conventional Commits
- **AI Agent Integration:** Multi-agent support via configuration files
  - `.cursorrules` for Cursor AI
  - `.github/copilot-instructions.md` for GitHub Copilot
  - `.aiderrc` for Aider (Claude Code)
  - `.codexrc` for OpenAI Codex
  - `.gemini/` for Gemini CLI and Antigravity
- **Testing:** Standards validation via scripts
- **Deployment:** Git submodule or direct clone distribution

## 🏗 Coding Standards (Non-Negotiables)

- **Naming:** Follow language-specific conventions (see `standards/languages/`)
  - Python: `snake_case` for functions/variables, `PascalCase` for classes
  - JavaScript/TypeScript: `camelCase` for variables/functions, `PascalCase` for classes
  - Rust: `snake_case` for functions/variables, `PascalCase` for types
- **Patterns:** Clean Architecture with strict dependency rules (Domain → Application → Infrastructure)
- **Safety:** 
  - Do not modify files ending in `.secret` or `.tfstate`
  - Do not modify `.standards_tmp/` directory (temporary files only)
  - Preserve existing standards structure and numbering
- **Security:** Follow P0-P3 severity model in `standards/security/sec-01_security_standards.md`. P0/P1 violations block merge.
- **Commits:** Follow Conventional Commits format (`feat:`, `fix:`, `docs:`, `refactor:`, etc.)
- **Architecture:** SOLID principles required, violations must be justified
- **Documentation:** All standards must be documented in Markdown with clear examples

## 🚦 Definition of Done

1. Code passes shell script validation (`bash -n` for syntax)
2. Standards follow existing format and structure
3. Documentation in `/docs` is updated for user-facing changes
4. `.cursorrules` is updated if new standards are added
5. Git commits follow Conventional Commits format
6. Changes are tested in a sample project integration

## 📁 Repository Structure

```
.
├── .cursorrules                    # Cursor AI configuration
├── .gemini/                        # Gemini CLI & Antigravity config
│   ├── GEMINI.md                   # This file (primary agent context)
│   ├── settings.json               # Gemini CLI settings
│   └── active_mission.log          # Active Antigravity mission URL (gitignored)
├── Makefile                        # Automation targets
├── standards/                      # All standards documents
│   ├── architecture/              # Core architecture & automation
│   ├── languages/                 # Language-specific standards
│   ├── process/                   # Process & workflow standards
│   ├── security/                  # Security standards
│   └── agents/                    # Agent-specific configurations
├── scripts/                       # Automation scripts
└── docs/                          # User documentation
```

## 🔄 Agent Workflow Protocol

When working with this repository, agents must follow the A-P-E (Analyze, Plan, Execute) cycle:

### Analyze
- Read relevant standards files in `standards/` directory
- Check `.cursorrules` for overall project context
- Review existing patterns before making changes
- Identify affected documentation files

### Plan
- Generate a plan before writing code: `/plan "Add new language standard"`
- Identify all files that need updates (standards, `.cursorrules`, docs)
- Consider impact on existing integrations
- Check for breaking changes

### Execute
- Use `gemini edit` to provide a diff for human review rather than overwriting files blindly
- Follow existing file structure and naming conventions
- Update related documentation
- Test changes in a sample project if possible

## 🛡️ Safety Constraints

- **Never modify:**
  - Files in `.standards_tmp/` (temporary only)
  - Files ending in `.secret` or `.tfstate`
  - Git history or commit messages (unless explicitly requested)
- **Always preserve:**
  - Existing standards file naming (e.g., `arch-01_`, `lang-01_`, `proc-01_`)
  - Directory structure and organization
  - Backward compatibility for existing integrations
- **Always update:**
  - `.cursorrules` when adding new standards
  - Documentation in `/docs` for user-facing changes
  - `CHANGELOG.md` for significant changes

## 📚 Key Standards Files

- **Architecture:** `standards/architecture/arch-01_project_standards_and_architecture.md`
- **Automation:** `standards/architecture/arch-02_automation_standards.md`
- **Cursor Integration:** `standards/architecture/arch-03_cursor_automation_standards.md`
- **Language Standards:** `standards/languages/lang-01_python_standards.md` through `lang-11_ruby_on_rails_standards.md`
- **Process Standards:** `standards/process/proc-01_documentation_standards.md` through `proc-04_agent_workflow_standards.md`
- **Security Standards:** `standards/security/sec-01_security_standards.md` - P0-P3 security guidelines

## 🔗 Integration Points

- **Setup Script:** `scripts/setup.sh` - Installs standards in client projects
- **Sync Script:** `scripts/sync-standards.sh` - Updates standards in client projects
- **Makefile:** `Makefile` - Provides automation targets (`make sync-standards`, `make pr`, etc.)
- **Install Script:** `install.sh` - One-command installation for client projects

## 🎯 Agent Onboarding

When starting work on this repository:

1. Read `.gemini/GEMINI.md` (this file) to understand architecture and constraints
2. Review `standards/architecture/arch-01_project_standards_and_architecture.md` for core principles
3. Check `.cursorrules` for Cursor AI integration patterns
4. Use checkpointing via Gemini CLI before attempting any refactors
5. Do not proceed with multi-file edits without first outputting a 'Proposed Logic Plan'
6. Verify changes don't break existing integrations

## 📝 Change Workflow

1. **Identify scope:** Which standards/documents are affected?
2. **Plan changes:** Create a plan showing all files to modify
3. **Implement:** Make changes following existing patterns
4. **Update integration:** Update `.cursorrules` if standards changed
5. **Update docs:** Update relevant documentation in `/docs`
6. **Test:** Verify changes work in a sample project
7. **Commit:** Use Conventional Commits format

## 🚨 Common Pitfalls

- **Don't:** Renumber standards files (breaks references)
- **Don't:** Modify `.standards_tmp/` files (temporary only)
- **Don't:** Skip updating `.cursorrules` when adding standards
- **Don't:** Break backward compatibility without justification
- **Do:** Follow existing file structure and naming
- **Do:** Update documentation for user-facing changes
- **Do:** Test changes in a sample project integration
