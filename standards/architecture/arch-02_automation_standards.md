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
* **Requirement:** Must provision containers (Docker Compose) or strict virtual environments. On a multi-toolchain repo it MUST provision **every** toolchain a fresh machine needs (e.g. JS deps *and* the Rust toolchain) plus the git hooks — a contributor runs one command and is ready.
* **Requirement:** Dependency installs use the lockfile (frozen/`ci`/`--locked` mode) so a fresh checkout or worktree reproduces the committed versions exactly.
* **Post-condition:** System is ready for coding immediately after execution; pair with `make doctor` to verify every required tool is present.

### `make test`
* **Goal:** Verify code integrity.
* **Action:** Runs all unit and integration tests.

### `make test-e2e`
* **Applicability:** Required for projects with a browser/integration surface (web app, API server, CLI with integration paths). Projects without one — a pure library, or a docs/standards repo — MAY omit it; `make verify` then runs only the applicable subset.
* **Goal:** Verify end-to-end behavior against a built artifact.
* **Action:** Runs the browser/integration e2e suite (e.g. Playwright).
* **Requirement:** MUST (re)build the artifact the runner serves before executing — a runner that serves a prebuilt `dist/` will otherwise validate **stale** output and report false greens. Either rebuild as a prerequisite or fail if the build is stale.

### `make verify` (pre-merge gate)
* **Goal:** The single command that must pass before merge.
* **Action:** Runs the full pipeline applicable to the project: typecheck + lint + format check + tests + **build + `test-e2e`** (e2e included wherever the project defines it, per the applicability note above). "Format check" is the **non-mutating** counterpart of `make fmt` — e.g. `prettier --check`, `cargo fmt --check`, `ruff format --check` — so the gate fails on unformatted code instead of silently reformatting it.
* **Why:** A gate of only typecheck/lint/unit lets UI and integration regressions through (observed: multiple UI regressions shipped "unit-green" because e2e was excluded from the local gate). A smoke subset (single browser) is acceptable for the fast local loop; run the full matrix in CI.

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

### `make hooks`
* **Goal:** (Re)install git hooks for the current checkout.
* **Action:** Re-runs the hook installer (e.g. `pnpm exec lefthook install`, `pre-commit install`) so `.git/hooks/*` point at the current working tree.
* **Why:** Hook installers can leave `.git/hooks/*` hardcoding a *deleted* worktree's path; switching between worktrees then breaks committing. `make hooks` repairs this. Declare the hook tool as a **root** dependency so it resolves at the repo root where `.git` lives, not only inside a sub-package.

### `make pr`
* **Goal:** Create and populate a GitHub Pull Request from current branch to main.
* **Action:** Pushes current branch (if not already pushed), then creates a PR using GitHub CLI (`gh`) with auto-generated title and description from recent commits.
* **Requirement:** GitHub CLI (`gh`) must be installed and authenticated.
* **Post-condition:** PR is created on GitHub with title, description, and proper base/head branches.

### `make sync-standards`
* **Goal:** Pull the latest coding standards and regenerate every declared AI agent config.
* **Action:** Runs `./.standards/scripts/sync-standards.sh` **from the project root**. The script reads `agents:` from `.standards.yml` and only touches what those agents need.
* **Post-condition:** Agent configs (`CLAUDE.md`, `.cursorrules`, `AGENTS.md`, …) are up to date, or staged to `.standards-pending/` when customized.
* **Never:** `make -C .standards ...` or `cp .standards/.cursorrules .cursorrules`. Running from inside the submodule resolves the project root to `.standards/`, and the standards repo's own `.cursorrules` would overwrite the project's assembled one.

### `make diff-standards`
* **Goal:** Preview what `make sync-standards` would change.
* **Action:** Runs `./.standards/scripts/diff-standards.sh`. Add `--exit-code` to fail (exit 1) when any config would change — usable as a CI gate.

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

### Implementation Example for `make sync-standards` and `make diff-standards`

Both targets invoke the scripts from the project root so that `PROJECT_ROOT` resolves to the consumer project, not the submodule:

```makefile
.PHONY: sync-standards diff-standards
sync-standards: ## Sync project standards to latest version (run from project root)
	@if [ -d ".standards" ]; then \
		./.standards/scripts/sync-standards.sh; \
	else \
		echo "❌ .standards directory not found. Run install script first."; \
		exit 1; \
	fi

diff-standards: ## Show what sync-standards would change (add --exit-code to gate CI)
	@if [ -d ".standards" ]; then \
		./.standards/scripts/diff-standards.sh; \
	else \
		echo "❌ .standards directory not found. Run install script first."; \
		exit 1; \
	fi
```

This implementation:

* Checks for standards submodule at `.standards`
* Runs the scripts from the project root (never `make -C .standards`)
* Lets `sync-standards.sh` honour the `agents:` list in `.standards.yml` for every side effect
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

## 8. Toolchain Workarounds Carry an Issue and an Expiry

A build-system workaround — a deprecated flag kept because its replacement is not ready (`--build-system native`, "currently deprecated, revisit on upgrades"), a tool pinned one version back, `--legacy-peer-deps`, an environment variable that silences a new check, a package patch under `patches/` — is borrowed time. Without a date it becomes permanent: the person who added it leaves, the upgrade that would remove it never happens, and the deprecated path finally breaks at the worst moment.

Every workaround in a Makefile, script, CI definition, lockfile override or toolchain file carries two things, adjacent to the workaround itself:

1. **`TODO(#issue)`** — the issue that tracks removing it, per the Work Tracking rules in `core-standards.md`. The issue body states what the workaround does, what has to change upstream, and how to verify the fix.
2. **An expiry check** — a condition CI can evaluate that fails when the workaround should have gone: a date (`workaround-expiry: date 2026-12-31`) or, better, a version threshold (`workaround-expiry: version xcodebuild 17.0`, `workaround-expiry: version node 24.0.0`). When the condition trips, the gate fails with the `TODO(#issue)` text and the workaround is removed or re-justified with a new issue and a new expiry. A workaround never silently outlives its reason.

```makefile
# TODO(#412): --build-system native is deprecated in Xcode 16; remove once the
# SwiftPM default builds the macOS target.
# workaround-expiry: version xcodebuild 17.0
SWIFT_BUILD_FLAGS += --build-system native
```

`make verify` (§2) runs a `check-workarounds` step that greps for `workaround-expiry:` markers, evaluates each condition (the date is in the past, or the installed tool reports a version at or above the threshold) and fails naming the marker and its `TODO(#issue)`. A marker with no `TODO(#issue)` within the two preceding lines fails outright: an expiry with no owner is not tracked. A workaround that is still needed when it expires gets a *new* expiry and a comment on the issue saying why — the re-decision is the point, not the deadline.

The checker is **consumer-supplied** (this repository ships the marker grammar, not the script, because the version half depends on which tools the project runs and how each reports its version). Its contract: exit non-zero when any marker's condition holds or any marker lacks a `TODO(#issue)` within two lines above it, naming each offender with file, line and the TODO text. The date half is a few lines of shell and is enough to start with:

```bash
# scripts/check-workarounds.sh (date markers only; add `version <tool> <min>` per tool)
today=$(date -u +%Y-%m-%d)
rc=0
# `done < <(…)` keeps the loop in this shell so rc survives; a `grep | while`
# pipeline would run the loop in a subshell and always exit 0.
while IFS=: read -r file line text; do
  due=$(printf '%s' "$text" | sed -n 's/.*workaround-expiry: date \([0-9][0-9]*-[0-9][0-9]-[0-9][0-9]\).*/\1/p')
  todo=$(sed -n "$((line > 2 ? line - 2 : 1)),${line}p" "$file" | grep -o 'TODO(#[0-9][0-9]*)' | head -1)   # at least one digit: `TODO(#)` is not an owner
  [ -n "$todo" ] || { echo "FAIL $file:$line workaround-expiry without TODO(#issue)"; rc=1; }
  # A real calendar date, not just the shape: `9999-99-99` would sort as "future" forever.
  [ -n "$due" ] && [ "$(date -u -d "$due" +%Y-%m-%d 2>/dev/null)" = "$due" ] \
    || { echo "FAIL $file:$line malformed date marker '$due' (want a real YYYY-MM-DD)"; rc=1; continue; }
  if [ ! "$due" \> "$today" ]; then echo "FAIL $file:$line workaround expired $due ($todo)"; rc=1; fi
# Markers live next to the workaround (Makefile, scripts, CI, lockfile
# overrides), never in prose: Markdown and the vendored `.standards/` tree
# (this document mentions the marker several times) are excluded.
done < <(git grep -n 'workaround-expiry: date ' -- . ':!scripts/check-workarounds.sh' ':!*.md' ':!.standards/' ':!docs/')
exit "$rc"
```

A `version <tool> <min>` marker compares `<tool> --version` (normalised to `major.minor.patch`) against `<min>` with the same numeric component ordering the changelog-tags check uses; a tool that is not installed in CI is reported as "cannot evaluate", never as passed.
