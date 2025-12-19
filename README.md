# Project Standards Repository

Comprehensive development standards and guidelines for software projects, designed to work seamlessly with Cursor AI, GitHub Copilot, Claude Code (Aider), OpenAI Codex, Gemini CLI, Google Antigravity, and other AI coding assistants.

## 🚀 Quick Install

**Install standards in your project with one command:**

```bash
curl -fsSL https://raw.githubusercontent.com/c65llc/coding_standards/main/install.sh | bash
```

**Or specify a custom repository URL:**

```bash
STANDARDS_REPO_URL="https://github.com/c65llc/coding_standards" \
  curl -fsSL https://raw.githubusercontent.com/c65llc/coding_standards/main/install.sh | bash
```

The installer will:

- ✅ Add standards as a git submodule
- ✅ Set up `.cursorrules` for Cursor AI
- ✅ Set up `.github/copilot-instructions.md` for GitHub Copilot
- ✅ Set up `.aiderrc` for Aider (Claude Code)
- ✅ Set up `.codexrc` for OpenAI Codex
- ✅ Set up `.gemini/GEMINI.md` and `.gemini/settings.json` for Gemini CLI & Antigravity
- ✅ Add `make sync-standards` target to your Makefile
- ✅ Configure git hooks for automatic updates

**After installation:**

1. Restart your IDE/editor to load AI agent configurations
2. Sync standards later: `make sync-standards`
3. See [Multi-Agent Guide](docs/MULTI_AGENT_GUIDE.md) for agent-specific setup

---

## 📁 Repository Structure

```text
.
├── .cursorrules                    # Cursor AI configuration (references all standards)
├── .gemini/                        # Gemini CLI & Antigravity configuration
│   ├── GEMINI.md                   # Repository intelligence for AI agents
│   └── settings.json              # Gemini CLI settings
├── Makefile                        # Automation targets
│
├── standards/                      # All standards documents
│   ├── architecture/              # Core architecture & automation
│   │   ├── 00_project_standards_and_architecture.md
│   │   ├── 01_automation_standards.md
│   │   └── 02_cursor_automation_standards.md
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
│   └── process/                   # Process & workflow standards
│       ├── 12_documentation_standards.md
│       ├── 13_git_version_control_standards.md
│       └── 14_code_review_expectations.md
│
├── scripts/                       # Automation scripts
│   ├── setup.sh                  # Setup standards in a project
│   └── sync-standards.sh         # Sync standards updates
│
└── docs/                          # Documentation
    ├── README.md                 # Detailed overview (this file)
    ├── QUICK_START.md            # 5-minute setup guide
    ├── SETUP_GUIDE.md            # Detailed setup instructions
    └── INTEGRATION_GUIDE.md       # Complete integration guide
```

## 📖 Manual Installation

If you prefer manual setup or the installer doesn't work:

### Option 1: Git Submodule (Recommended)

```bash
# In your project root
git submodule add https://github.com/c65llc/coding_standards.git .standards
.standards/scripts/setup.sh
```

### Option 2: Direct Clone

```bash
git clone https://github.com/c65llc/coding_standards.git .standards
.standards/scripts/setup.sh
```

### Option 3: Add sync-standards to Existing Makefile

If you already have a Makefile, add this target:

```makefile
.PHONY: sync-standards
sync-standards: ## Sync project standards to latest version
    @if [ -d ".standards" ]; then \
        ./.standards/scripts/sync-standards.sh; \
    else \
        echo "❌ .standards directory not found. Run install script first."; \
        exit 1; \
    fi
```

## 📚 Standards Overview

### Architecture Standards

- **Project Standards & Architecture** - Core architecture, SOLID principles, naming conventions
- **Automation Standards** - Makefile targets and automation requirements
- **Cursor Automation Standards** - Cursor-specific interaction modes

### Language Standards

Standards for 9 languages:

- Python, Java, Kotlin, Swift, Dart
- TypeScript, JavaScript, Rust, Zig

Each includes: package management, code style, naming conventions, testing, error handling, and documentation.

### Process Standards

- **Documentation Standards** - ADR, code docs, changelog, user docs
- **Git & Version Control** - Workflow, commits, branching
- **Code Review Expectations** - Review process and best practices

## 🛠️ Usage

### Setup in Project

```bash
make setup
# or
./scripts/setup.sh
```

### Sync Updates

```bash
make sync-standards
# or
./scripts/sync-standards.sh
```

### Check Status

```bash
make check-standards
```

## 📖 Documentation

- **[QUICK_START.md](docs/QUICK_START.md)** - Get started in 5 minutes
- **[SETUP_GUIDE.md](docs/SETUP_GUIDE.md)** - Detailed setup instructions
- **[INTEGRATION_GUIDE.md](docs/INTEGRATION_GUIDE.md)** - Complete integration guide
- **[MULTI_AGENT_GUIDE.md](docs/MULTI_AGENT_GUIDE.md)** - Multi-agent support (Copilot, Aider, Codex)

## 🔄 Maintenance

### Making Changes

1. Edit standards files in `standards/` directories
2. Update `.cursorrules` if adding new standards
3. Commit with conventional format:

   ```bash
   git commit -m "docs(python): update pytest requirements"
   ```

### Versioning

Tag releases for teams to pin versions:

```bash
git tag -a v1.0.0 -m "Release 1.0.0"
git push origin main --tags
```

## 🤝 Contributing

1. Create feature branch: `git checkout -b feature/new-standard`
2. Make changes following existing format
3. Update `.cursorrules` if adding new files
4. Commit with conventional format
5. Open Pull Request

## 📝 License

[Specify your license here]

## 🔗 Links

- [Quick Start Guide](docs/QUICK_START.md)
- [Setup Guide](docs/SETUP_GUIDE.md)
- [Integration Guide](docs/INTEGRATION_GUIDE.md)
