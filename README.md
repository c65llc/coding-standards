# Project Standards Repository

Comprehensive development standards and guidelines for software projects, designed to work seamlessly with Cursor AI, GitHub Copilot, Claude Code (Aider), OpenAI Codex, and other AI coding assistants.

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
- ✅ Set up `CLAUDE.md` template for Claude Code
- ✅ Set up `.claude/settings.json` for Claude Code permissions
- ✅ Add `make sync-standards` target to your Makefile
- ✅ Configure git hooks for automatic updates

**After installation:**

1. Restart your IDE/editor to load AI agent configurations
2. Sync standards later: `make sync-standards`
3. See [Multi-Agent Guide](docs/MULTI_AGENT_GUIDE.md) for agent-specific setup

---

## 🔧 GitHub Project Lifecycle Automation

**NEW**: Seamless CLI-driven workflow connecting issues to Draft PRs via GitHub Projects V2.

```bash
# Install gh-task CLI tool
ln -s .standards/bin/gh-task bin/gh-task

# Create and start working on an issue
gh-task create "Add user authentication"
gh-task start 42

# Submit when ready (runs tests, creates Draft PR)
gh-task submit
```

**Features:**
- ✅ Automatic GitHub Projects V2 status updates
- ✅ Branch management with naming conventions  
- ✅ Pre-flight test validation
- ✅ Draft PR creation with issue linking
- ✅ AI agent and human developer support

**Documentation:**
- [Quick Start Guide](docs/GH_TASK_QUICKSTART.md) - Get started in 5 minutes
- [gh-task CLI Guide](docs/GH_TASK_GUIDE.md) - Complete command reference
- [Tooling Guide](docs/TOOLING.md) - Architecture and AI agent instructions
- [Reusable GitHub Actions Workflows](.github/workflows/) - CI/CD automation

---

## 📁 Repository Structure

```text
.
├── .cursorrules                    # Cursor AI configuration (references all standards)
├── Makefile                        # Automation targets
│
├── bin/                            # CLI utilities
│   └── gh-task                    # GitHub Project lifecycle management CLI
│
├── .github/                        # GitHub configuration
│   ├── workflows/                 # Reusable GitHub Actions workflows
│   │   ├── lifecycle-sync.yml    # Auto-sync Project V2 status on PR events
│   │   └── definition-of-done.yml # Quality checks for PRs
│   └── PULL_REQUEST_TEMPLATE/    # PR templates with issue linking
│       └── default.md
│
├── standards/                      # All standards documents
│   ├── architecture/              # Core architecture & automation
│   │   ├── 00_project_standards_and_architecture.md
│   │   ├── 01_automation_standards.md
│   │   ├── 02_cursor_automation_standards.md
│   │   ├── 16_data_versioning_and_migration_standards.md
│   │   └── 17_resilient_architecture_patterns.md
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
│   ├── process/                   # Process & workflow standards
│   │   ├── 12_documentation_standards.md
│   │   ├── 13_git_version_control_standards.md
│   │   ├── 14_code_review_expectations.md
│   │   └── 15_agent_workflow_standards.md
│   └── agents/                    # AI agent configurations
│       ├── copilot/               # GitHub Copilot
│       ├── aider/                 # Aider
│       ├── codex/                 # OpenAI Codex
│       └── claude-code/           # Claude Code (CLAUDE.md template, settings)
│
├── scripts/                       # Automation scripts
│   ├── setup.sh                  # Setup standards in a project
│   └── sync-standards.sh         # Sync standards updates
│
├── templates/                      # Configuration templates
│   ├── settings.json.example     # GitHub Projects V2 config template
│   └── gh-task.conf.example      # Alternative gh-task config template
│
└── docs/                          # Documentation
    ├── README.md                 # Detailed overview
    ├── QUICK_START.md            # 5-minute setup guide
    ├── SETUP_GUIDE.md            # Detailed setup instructions
    ├── INTEGRATION_GUIDE.md       # Complete integration guide
    ├── MULTI_AGENT_GUIDE.md      # Multi-agent AI support guide
    ├── GH_TASK_GUIDE.md          # gh-task CLI complete reference
    └── TOOLING.md                # GitHub Project lifecycle automation guide
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
- **Data Versioning & Migration** - Schema versioning, migration strategies, backward compatibility
- **Resilient Architecture Patterns** - Per-module coverage gates, pure render logic, responsive design, error layering

### Language Standards

Standards for 9 languages:

- Python, Java, Kotlin, Swift, Dart
- TypeScript, JavaScript, Rust, Zig

Each includes: package management, code style, naming conventions, testing, error handling, and documentation.

### Process Standards

- **Documentation Standards** - ADR, code docs, changelog, user docs
- **Git & Version Control** - Workflow, commits, branching
- **Code Review Expectations** - Review process and best practices
- **Agent Workflow Standards** - Worktree isolation, AI guide templates, permission models, devloop pattern

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

### Standards & Setup
- **[QUICK_START.md](docs/QUICK_START.md)** - Get started in 5 minutes
- **[SETUP_GUIDE.md](docs/SETUP_GUIDE.md)** - Detailed setup instructions
- **[INTEGRATION_GUIDE.md](docs/INTEGRATION_GUIDE.md)** - Complete integration guide
- **[MULTI_AGENT_GUIDE.md](docs/MULTI_AGENT_GUIDE.md)** - Multi-agent support (Copilot, Aider, Codex)

### GitHub Project Lifecycle Automation
- **[GH_TASK_QUICKSTART.md](docs/GH_TASK_QUICKSTART.md)** - gh-task quick start (5 minutes)
- **[GH_TASK_GUIDE.md](docs/GH_TASK_GUIDE.md)** - Complete gh-task CLI reference
- **[TOOLING.md](docs/TOOLING.md)** - Architecture and AI agent instructions

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
