# Document 2: Automation & Workflows

**Filename:** `arch-02_automation_standards.md`

> **Usage:** This rules file instructs the AI to always check for or generate a `Makefile` that wraps the underlying tech stack (npm, pip, cargo, etc).

```markdown
# Automation Standards

## 1. Meta-Automation Tool
* **Standard:** `GNU Make` is the single entry point for all project tasks.
* **Abstraction:** The `Makefile` must wrap underlying package managers (npm, poetry, cargo). Do not run language-specific commands directly in CI/CD or local dev.

## 2. Required Make Targets
Every project MUST include the following targets in the root `Makefile`:

### `make bootstrap`
* **Goal:** Get local machine ready for development
* **Requirement** Must perform any tasks that can't be handled by `make dev`
* **Post-condition:** Make Dev can run without errors

### `make dev`
* **Goal:** Setup stable local development environment.
* **Requirement:** Must provision containers (Docker Compose) or strict virtual environments.
* **Post-condition:** System is ready for coding immediately after execution.

### `make test`
* **Goal:** Verify code integrity.
* **Action:** Runs all unit and integration tests.

### `make lint`
* **Goal:** Static analysis.
* **Action:** Runs linters (ESLint, Pylint, Ruff) and type checkers.

### `make lint-fix`
* **Goal:** Automatically fix linting and static analysis issues.
* **Action:** Runs linters and static analysis tools with auto-fix capabilities (e.g., `eslint --fix`, `ruff check --fix`, `cargo clippy --fix`).
* **Post-condition:** Automatically fixable issues are resolved in the codebase.

### `make build`
* **Goal:** Compile/Prepare assets.
* **Action:** Produces executable artifacts or optimized bundles (dist/ folder).

### `make run`
* **Goal:** Execute the project.
* **Action:** Stands up the application locally (e.g., `docker-compose up` or `uvicorn`).

### `make fmt`
* **Goal:** Standardize code style.
* **Action:** Auto-formats code (Prettier, Ruff, Rustfmt) across the entire repo.

### `make repo-setup`
* **Goal:** Initialize version control.
* **Action:** Configures git hooks (pre-commit), submodules, and local git settings.

### `make pr`
* **Goal:** Create and populate a GitHub Pull Request from current branch to main.
* **Action:** Pushes current branch (if not already pushed), then creates a PR using GitHub CLI (`gh`) with auto-generated title and description from recent commits.
* **Requirement:** GitHub CLI (`gh`) must be installed and authenticated.
* **Post-condition:** PR is created on GitHub with title, description, and proper base/head branches.

### `make setup-cursor`
* **Goal:** Install or update Cursor AI rules configuration.
* **Action:** Copies or updates `.cursorrules` file from standards repository (`.standards/.cursorrules` if using submodule, or from standards installation).
* **Post-condition:** `.cursorrules` file exists in project root and is up to date with standards.
* **Note:** This target is automatically called by `make sync-standards` when syncing standards in projects using the standards repository.

### `make ls`
* **Goal:** List all available make targets.
* **Action:** Dumps a simple list of all defined targets (without descriptions).
* **Usage:** Quick reference for available commands. Complements `make help` which shows descriptions.

## 3. Implementation Guidelines
* **Phony Targets:** Always declare `.PHONY` for all commands.
* **Help:** Include a `help` target that lists commands and descriptions (default target).
* **List Targets:** Include an `ls` target that lists all available make targets without descriptions for quick reference.
* **Idempotency:** Commands should be safe to run multiple times without side effects.
* **Temporary Files:** All temporary files created by standards-related scripts or Cursor AI commands MUST be placed in `.standards_tmp/` directory at the project root. This directory should be added to `.gitignore` in all projects using the standards (automatically handled by setup scripts).

### Implementation Example for `make ls`

The `ls` target should extract and list all target names from the Makefile:

```makefile
.PHONY: ls
ls: ## List all available make targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sed 's/:.*//' | sort
```

This implementation:

* Extracts targets that have descriptions (matches the pattern used by `help` target)
* Removes the colon and everything after it
* Sorts the list alphabetically
* Produces a clean list of target names only

### Implementation Example for `make setup-cursor`

The `setup-cursor` target should install or update `.cursorrules` from the standards repository:

```makefile
.PHONY: setup-cursor
setup-cursor: ## Install or update Cursor AI rules configuration
	@if [ -d ".standards" ] && [ -f ".standards/.cursorrules" ]; then \
		cp .standards/.cursorrules .cursorrules && \
		echo "✅ .cursorrules updated from .standards"; \
	elif [ -f ".standards/.cursorrules" ]; then \
		cp .standards/.cursorrules .cursorrules && \
		echo "✅ .cursorrules installed"; \
	else \
		echo "⚠️  Standards directory not found. Run setup script first."; \
		exit 1; \
	fi
```

This implementation:

* Checks for standards submodule at `.standards`
* Copies `.cursorrules` from standards to project root
* Provides clear feedback on success or failure
* Is idempotent (safe to run multiple times)

### Implementation Example for `make pr`

The `pr` target should create a GitHub PR from the current branch to main, using Cursor AI to generate the title and body:

```makefile
.PHONY: pr
pr: ## Create and populate a GitHub Pull Request from current branch to main
	@if ! command -v gh >/dev/null 2>&1; then \
		echo "❌ GitHub CLI (gh) not found. Install from: https://cli.github.com"; \
		exit 1; \
	fi
	@CURRENT_BRANCH=$$(git branch --show-current); \
	BASE_BRANCH="main"; \
	if [ "$$CURRENT_BRANCH" = "$$BASE_BRANCH" ]; then \
		echo "❌ Cannot create PR from $$BASE_BRANCH to itself"; \
		exit 1; \
	fi; \
	echo "📤 Pushing branch $$CURRENT_BRANCH..."; \
	git push -u origin $$CURRENT_BRANCH 2>/dev/null || git push 2>/dev/null || true; \
	if [ -z "$$PR_TITLE" ] || [ -z "$$PR_BODY" ]; then \
		echo "🔍 Generating PR information for Cursor AI..."; \
		PR_INFO_FILE=$$(./scripts/generate-pr-content.sh $$BASE_BRANCH 2>/dev/null || \
			.standards/scripts/generate-pr-content.sh $$BASE_BRANCH 2>/dev/null || \
			echo ""); \
		if [ -n "$$PR_INFO_FILE" ] && [ -f "$$PR_INFO_FILE" ]; then \
			echo "📝 PR information available at: $$PR_INFO_FILE"; \
			echo "💡 Use '\\pr' in Cursor chat to generate AI-powered title and body"; \
			echo "   Or provide manually: PR_TITLE='...' PR_BODY='...' make pr"; \
		fi; \
		if [ -z "$$PR_TITLE" ]; then \
			PR_TITLE=$$(git log $$BASE_BRANCH..HEAD --oneline --format="%s" | head -1); \
		fi; \
		if [ -z "$$PR_BODY" ]; then \
			PR_BODY=$$(git log $$BASE_BRANCH..HEAD --oneline --format="- %s" | head -20); \
			if [ -z "$$PR_BODY" ]; then \
				PR_BODY="No commits found between $$BASE_BRANCH and $$CURRENT_BRANCH"; \
			fi; \
		fi; \
	else \
		echo "✅ Using provided PR_TITLE and PR_BODY from Cursor AI"; \
	fi; \
	echo "🚀 Creating PR: $$PR_TITLE"; \
	gh pr create --base $$BASE_BRANCH --head $$CURRENT_BRANCH --title "$$PR_TITLE" --body "$$PR_BODY" || \
		echo "⚠️  PR may already exist. Check: gh pr view"
```

This implementation:

* Checks for GitHub CLI (`gh`) installation
* Validates current branch is not the base branch
* Pushes current branch to remote if not already pushed
* Generates PR information file using `generate-pr-content.sh` script
* Accepts `PR_TITLE` and `PR_BODY` as environment variables (populated by Cursor AI via `\pr` command)
* Falls back to commit-based generation if Cursor AI content not available
* Creates PR using GitHub CLI with AI-generated or fallback title and description
* Handles case where PR already exists gracefully

**Cursor AI Integration:**

* When user types `\pr` in Cursor chat, Cursor reads the PR information file
* Cursor generates an improved title and body based on code changes
* Cursor then calls: `PR_TITLE="<generated>" PR_BODY="<generated>" make pr`

## 4. Self-Documenting Make Targets

Every Makefile phony target MUST include a `## description` comment on the same line as the target declaration. This enables `make ls` to auto-list all targets with descriptions.

### Convention

```makefile
my-target: ## Short description of what this target does
	@echo "Running my-target"
```

### Required `ls` Target

```makefile
.PHONY: ls
ls: ## List all available make targets with descriptions
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
```

Targets without `## description` will not appear in `make ls`. This is intentional — internal helper targets can be hidden by omitting the description.

## 5. Per-Module Coverage Gates

Coverage baselines should be configurable per-module via Make variables, not a single global threshold:

```makefile
CORE_COV_MIN  ?= 100
APP_COV_MIN   ?= 95
INFRA_COV_MIN ?= 95

coverage-check: ## Enforce per-module coverage baselines
	@echo "Checking coverage baselines..."
	# Run coverage tool per module and compare against threshold
```

**95% coverage is the absolute minimum for any module.** Projects may raise these values but never lower them below 95%. Use test containers, mocks, and in-memory substitutes to achieve infrastructure coverage.

## 6. Seed Data Targets

Projects with UI or data models SHOULD include targets for generating test/demo data:

### `make seed`

* **Goal:** Generate realistic development seed data.
* **Action:** Runs a seed generator that produces sample data for local development.
* **Post-condition:** Seed data is written to a well-known directory (e.g., `.dev/seed-realistic/`).

### `make seed-stress`

* **Goal:** Generate stress-test data for performance validation.
* **Action:** Produces large datasets for benchmarking and load testing.
* **Post-condition:** Stress data is written to a separate directory (e.g., `.dev/seed-stress/`).

### Guidelines

* Seed generators should be **idempotent** — running twice produces the same result (or supports a `--force` flag for regeneration).
* Seed generators should be **workspace members** (e.g., a `tools/my-seed/` crate), not standalone scripts, to ensure version consistency.
* The app should support loading seed data via an environment variable (e.g., `SEED_PATH`).

## 7. Devloop Target (UI Projects)

Projects with a graphical interface SHOULD include an agent-friendly development loop:

### `make setup-devloop`

* **Goal:** Install devloop dependencies (e.g., Node.js server, Playwright, etc.).
* **Action:** One-time setup for the devloop infrastructure.

### `make devloop`

* **Goal:** Start an HTTP server for autonomous UI iteration.
* **Action:** Launches a build/inspect cycle API (see `proc-04_agent_workflow_standards.md` for endpoint specification).
* **Post-condition:** Server is running and accessible at a documented port (e.g., `localhost:9010`).
