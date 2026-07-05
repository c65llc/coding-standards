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
│   │   └── arch-08_ci_cd_pipeline_standards.md
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
│   │   └── lang-13_elixir_standards.md
│   │
│   ├── process/                   # Process & workflow standards
│   │   ├── proc-01_documentation_standards.md
│   │   ├── proc-02_git_version_control_standards.md
│   │   ├── proc-03_code_review_expectations.md
│   │   └── proc-04_agent_workflow_standards.md
│   │
│   ├── security/                  # Security standards
│   │   └── sec-01_security_standards.md
│   │
│   ├── shared/                   # Shared standards for all agents
│   │   └── core-standards.md
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
│       │       └── elixir.txt
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
│       ├── codex/                 # Note: Codex now reads AGENTS.md at project root (.codexrc is deprecated)
│       │   └── .codexrc
│       └── gemini/                # Note: Gemini CLI uses .gemini/ at root (Gemini CLI convention)
│           └── (configs in .gemini/ at project root)
│
├── scripts/                        # 🔧 Automation scripts
│   ├── setup.sh                   # Setup standards in a project
│   ├── sync-standards.sh          # Sync standards updates
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
| Architecture | `standards/architecture/` | arch-01, arch-02, arch-04 through arch-08 |
| Languages | `standards/languages/` | lang-01 through lang-13 |
| Process | `standards/process/` | proc-01 through proc-04 |
| Security | `standards/security/` | sec-01 |

### Automation

| Type | Location | Files |
|------|----------|-------|
| Scripts | `scripts/` | setup.sh, sync-standards.sh |
| Makefile | Root | Makefile |
| Config | Root | .cursorrules |

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
