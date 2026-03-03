# Repository Structure

This document explains the reorganized file hierarchy for easier navigation and understanding.

## Directory Organization

```
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
│   │   └── arch-03_cursor_automation_standards.md
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
│   │   └── lang-11_ruby_on_rails_standards.md
│   │
│   ├── process/                   # Process & workflow standards
│   │   ├── proc-01_documentation_standards.md
│   │   ├── proc-02_git_version_control_standards.md
│   │   └── proc-03_code_review_expectations.md
│   │
│   ├── shared/                   # Shared standards for all agents
│   │   └── core-standards.md
│   │
│   └── agents/                    # AI agent-specific configurations
│       ├── copilot/
│       │   └── .github/
│       │       └── copilot-instructions.md
│       ├── aider/
│       │   └── .aiderrc
│       ├── codex/
│       │   └── .codexrc
│       └── gemini/                # Note: Gemini CLI uses .gemini/ at root (Gemini CLI convention)
│           └── (configs in .gemini/ at project root)
│
├── scripts/                        # 🔧 Automation scripts
│   ├── setup.sh                   # Setup standards in a project
│   └── sync-standards.sh          # Sync standards updates
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
| Architecture | `standards/architecture/` | arch-01 through arch-03 |
| Languages | `standards/languages/` | lang-01 through lang-11 |
| Process | `standards/process/` | proc-01 through proc-03 |

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

- **`.cursorrules`** - References `standards/architecture/`, `standards/languages/`, `standards/process/`
- **Scripts** - Updated to find `.cursorrules` in parent directory
- **Makefile** - Updated to reference `scripts/` directory
- **Documentation** - Updated to reflect new paths

## Migration Notes

If you have existing projects using the old structure:

1. **Update `.cursorrules`** - Paths now use `standards/` prefix
2. **Update scripts** - Use `scripts/setup.sh` instead of `setup.sh`
3. **Update Makefile** - Use `make setup` (automatically uses new paths)

The reorganization is backward-compatible through the updated scripts and `.cursorrules` file.

