# Repository Structure

This document explains the reorganized file hierarchy for easier navigation and understanding.

## Directory Organization

```text
.
├── .cursorrules                    # Cursor AI configuration (root level for easy access)
├── .gemini/                        # Gemini CLI & Antigravity configuration
│   ├── GEMINI.md                   # Repository intelligence for AI agents
│   └── settings.json              # Gemini CLI settings
├── Makefile                        # Automation targets
├── README.md                       # Main entry point and overview
│
├── standards/                      # 📋 All standards documents
│   ├── architecture/              # Core architecture & automation standards
│   │   ├── arch-01_project_standards_and_architecture.md
│   │   ├── arch-02_automation_standards.md
│   │   ├── arch-04_data_versioning_and_migration_standards.md
│   │   ├── arch-05_resilient_architecture_patterns.md
│   │   ├── arch-06_monorepo_workspace_standards.md
│   │   ├── arch-07_cross_platform_shared_core_standards.md
│   │   ├── arch-08_ci_cd_pipeline_standards.md
│   │   ├── arch-09_containerized_agent_dev_standards.md
│   │   └── arch-10_agent_tools_and_mcp_server_standards.md
│   │
│   ├── languages/                 # Language-specific standards
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
│   ├── process/                   # Process & workflow standards
│   │   ├── proc-01_documentation_standards.md
│   │   ├── proc-02_git_version_control_standards.md
│   │   ├── proc-03_code_review_expectations.md
│   │   ├── proc-04_agent_workflow_standards.md
│   │   └── proc-05_test_governance.md
│   │
│   ├── security/                  # Security standards
│   │   └── sec-01_security_standards.md
│   │
│   ├── shared/                   # Shared standards for all agents
│   │   └── core-standards.md
│   │
│   ├── skills/                    # Agent-neutral runbooks, emitted per agent by scripts/assemble-skills.sh
│   │   ├── merge-standards.md     # (.claude/skills/, .cursor/commands/, .github/prompts/, or a Skills index)
│   │   ├── standards-audit.md
│   │   ├── security-gate.md
│   │   ├── coverage-enforcer.md
│   │   ├── dependency-age-gate.md
│   │   ├── naming-convention.md
│   │   ├── config-assembly.md
│   │   └── setup-wizard.md
│   │
│   └── agents/                    # AI agent-specific configurations
│       ├── claude-code/
│       │   ├── base-claude-code.md
│       │   ├── settings.json.example
│       │   └── permissions/       # Language-specific Claude Code permissions
│       │       ├── python.txt
│       │       ├── rust.txt
│       │       ├── ruby.txt
│       │       ├── javascript.txt
│       │       ├── jvm.txt
│       │       ├── swift.txt
│       │       ├── dart.txt
│       │       ├── zig.txt
│       │       ├── go.txt
│       │       ├── elixir.txt
│       │       └── cpp.txt
│       ├── python/
│       │   └── ruff.toml          # Python linter/formatter config
│       ├── rust/
│       │   ├── rustfmt.toml       # Rust formatter config
│       │   └── clippy.toml        # Rust linter config
│       ├── ruby/
│       │   └── .rubocop.yml       # Ruby linter config
│       ├── javascript/
│       │   └── .prettierrc        # JS/TS formatter config
│       ├── copilot/
│       │   └── .github/
│       │       └── copilot-instructions.md
│       ├── aider/
│       │   └── .aiderrc
│       ├── codex/                 # Note: Codex reads AGENTS.md at project root (.codexrc is deprecated)
│       │   └── base-codex.md      # Assembled into AGENTS.md
│       └── gemini/                # Note: Gemini CLI uses .gemini/ at root (Gemini CLI convention)
│           ├── base-gemini.md
│           └── antigravity.md     # Antigravity Mission Isolation appendix to proc-04
│
├── templates/                      # 📄 Copy-and-fill templates for consumer projects
│   ├── docs/                      # ADR, spec, plan, design-pass, verification docs
│   │   ├── adr.md
│   │   ├── spec.md
│   │   ├── plan.md
│   │   ├── design-pass.md
│   │   └── verification.md
│   ├── cpp/                       # C++ tooling (lang-14): .clang-format, .clang-tidy, CMakePresets.json, ProjectWarnings.cmake
│   └── *.example                  # Workflow / config templates
│
├── scripts/                        # 🔧 Automation scripts
│   ├── setup.sh                   # Setup standards in a project
│   ├── sync-standards.sh          # Sync standards updates
│   ├── assemble-config.sh         # Assemble one agent config from base template + blocks (+ Skills index)
│   ├── assemble-skills.sh         # Emit standards/skills/ per agent (Claude skills, Cursor commands, Copilot prompts)
│   ├── doctor.sh                  # Standards health check (config, agents, hooks, worktrees)
│   ├── worktree-gc.sh             # Remove merged, gone and idle agent worktrees
│   ├── detect-languages.sh        # Detect project languages via manifest files
│   └── build-claude-settings.sh   # Build language-aware Claude Code settings
│
└── docs/                           # 📚 Documentation
    ├── README.md                  # Detailed guide (moved from root)
    ├── QUICK_START.md             # 5-minute setup guide
    ├── SETUP_GUIDE.md             # Detailed setup instructions
    └── INTEGRATION_GUIDE.md        # Complete integration guide
```

## Why This Structure?

### Benefits

1. **Logical Grouping**
   - Standards organized by category (architecture, languages, process)
   - Scripts separated from documentation
   - Clear separation of concerns

2. **Easy Navigation**
   - Find language standards in `standards/languages/`
   - Find process docs in `standards/process/`
   - All scripts in one place: `scripts/`

3. **Scalability**
   - Easy to add new languages (add to `standards/languages/`)
   - Easy to add new process standards (add to `standards/process/`)
   - Clear where new files belong

4. **Maintainability**
   - Related files grouped together
   - Clear file organization
   - Easier to understand for new contributors

## File Locations

### Standards Documents

| Category | Location | Files |
|----------|----------|-------|
| Architecture | `standards/architecture/` | arch-01, arch-02, arch-04 through arch-10 |
| Languages | `standards/languages/` | lang-01 through lang-14 |
| Process | `standards/process/` | proc-01 through proc-05 |
| Security | `standards/security/` | sec-01 |

### Automation

| Type | Location | Files |
|------|----------|-------|
| Scripts | `scripts/` | setup.sh, sync-standards.sh |
| Makefile | Root | Makefile |
| Config | Root | .cursorrules |
| Document templates | `templates/docs/` | adr.md, spec.md, plan.md, design-pass.md, verification.md |
| C++ tooling templates | `templates/cpp/` | .clang-format, .clang-tidy, CMakePresets.json, ProjectWarnings.cmake |

### Documentation

| Type | Location | Files |
|------|----------|-------|
| Guides | `docs/` | README.md, QUICK_START.md, SETUP_GUIDE.md, INTEGRATION_GUIDE.md |
| Overview | Root | README.md |

## Path References

All references have been updated:

- **`.cursorrules`** - References `standards/architecture/`, `standards/languages/`, `standards/process/`, `standards/security/`
- **Scripts** - Updated to find `.cursorrules` in parent directory
- **Makefile** - Updated to reference `scripts/` directory
- **Documentation** - Updated to reflect new paths

## Migration Notes

If you have existing projects using the old structure:

1. **Update `.cursorrules`** - Paths now use `standards/` prefix
2. **Update scripts** - Use `scripts/setup.sh` instead of `setup.sh`
3. **Update Makefile** - Use `make setup` (automatically uses new paths)

The reorganization is backward-compatible through the updated scripts and `.cursorrules` file.
