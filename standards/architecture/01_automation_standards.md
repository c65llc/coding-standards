# Document 2: Automation & Workflows

**Filename:** `01_automation_standards.md`

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

### `make build`
* **Goal:** Compile/Prepare assets.
* **Action:** Produces executable artifacts or optimized bundles (dist/ folder).

### `make run`
* **Goal:** Execute the project.
* **Action:** Stands up the application locally (e.g., `docker-compose up` or `uvicorn`).

### `make fmt`
* **Goal:** Standardize code style.
* **Action:** Auto-formats code (Prettier, Black, Rustfmt) across the entire repo.

### `make repo-setup`
* **Goal:** Initialize version control.
* **Action:** Configures git hooks (pre-commit), submodules, and local git settings.

### `make ls`
* **Goal:** List all available make targets.
* **Action:** Dumps a simple list of all defined targets (without descriptions).
* **Usage:** Quick reference for available commands. Complements `make help` which shows descriptions.

## 3. Implementation Guidelines
* **Phony Targets:** Always declare `.PHONY` for all commands.
* **Help:** Include a `help` target that lists commands and descriptions (default target).
* **List Targets:** Include an `ls` target that lists all available make targets without descriptions for quick reference.
* **Idempotency:** Commands should be safe to run multiple times without side effects.

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
