# Repository Structure

This document explains the reorganized file hierarchy for easier navigation and understanding.

## Directory Organization

```
.
├── .cursorrules                    # Cursor AI configuration (root level for easy access)
├── Makefile                        # Automation targets
├── README.md                       # Main entry point and overview
│
├── standards/                      # 📋 All standards documents
│   ├── architecture/              # Core architecture & automation standards
│   │   ├── 00_project_standards_and_architecture.md
│   │   ├── 01_automation_standards.md
│   │   └── 02_cursor_automation_standards.md
│   │
│   ├── languages/                 # Language-specific standards
│   │   ├── 03_python_standards.md
│   │   ├── 04_java_standards.md
│   │   ├── 05_kotlin_standards.md
│   │   ├── 06_swift_standards.md
│   │   ├── 07_dart_standards.md
│   │   ├── 08_typescript_standards.md
│   │   ├── 09_javascript_standards.md
│   │   ├── 10_rust_standards.md
│   │   └── 11_zig_standards.md
│   │
│   ├── process/                   # Process & workflow standards
│   │   ├── 12_documentation_standards.md
│   │   ├── 13_git_version_control_standards.md
│   │   └── 14_code_review_expectations.md
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
│       └── codex/
│           └── .codexrc
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
| Architecture | `standards/architecture/` | 00-02 |
| Languages | `standards/languages/` | 03-11 |
| Process | `standards/process/` | 12-14 |

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

