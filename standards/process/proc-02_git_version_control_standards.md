# Git & Version Control Standards

## 1. Repository Structure

### Branch Strategy

* **Main Branch:** `main` (or `master` for legacy). Protected branch. All production code.
* **Development Branch:** `develop` (optional). Integration branch for features.
* **Feature Branches:** `feature/description` (e.g., `feature/user-authentication`)
* **Bug Fixes:** `fix/description` (e.g., `fix/email-validation`)
* **Hotfixes:** `hotfix/description` (e.g., `hotfix/security-patch`)
* **Releases:** `release/version` (e.g., `release/1.2.0`)

### Branch Naming

* **Format:** `type/description` (kebab-case)
* **Types:** `feature`, `fix`, `hotfix`, `release`, `refactor`, `docs`, `test`
* **Description:** Concise, descriptive (3-5 words)

## 2. Commit Messages

### Conventional Commits Format

```text
<type>(<scope>): <subject>

<body>

<footer>
```

### Commit Types

* **feat:** New feature
* **fix:** Bug fix
* **docs:** Documentation changes
* **style:** Code style changes (formatting, missing semicolons)
* **refactor:** Code refactoring (no functional changes)
* **perf:** Performance improvements
* **test:** Adding or updating tests
* **chore:** Maintenance tasks (dependencies, build config)
* **ci:** CI/CD changes
* **build:** Build system changes

### Commit Guidelines

* **Subject:** Imperative mood, 50 characters or less, no period
* **Body:** Explain "what" and "why", wrap at 72 characters
* **Footer:** Reference issues/PRs: `Closes #123`, `Fixes #456`
* **Scope:** Optional, indicates area of change (e.g., `domain`, `api`, `ui`)

### Examples

```text
feat(domain): add user email validation

Implement RFC 5322 compliant email validation in Email value object.
Rejects invalid formats at domain boundary to fail fast.

Closes #123
```

```text
fix(api): handle null response in user endpoint

Return 404 instead of 500 when user not found. Prevents server
errors from propagating to client.

Fixes #456
```

## 3. Commit Best Practices

### Atomic Commits

* **One Logical Change:** Each commit should represent one complete, logical change
* **Small Commits:** Prefer multiple small commits over one large commit
* **Testable:** Each commit should leave the codebase in a working state

### Commit Frequency

* **Regular Commits:** Commit frequently (at least daily during active development)
* **Logical Units:** Commit when a logical unit of work is complete
* **Before Break:** Commit before leaving work for extended periods

### What to Commit

* **Source Code:** All source code, tests, and configuration
* **Documentation:** README, docs, comments
* **Configuration:** Build files, CI config, editor configs
* **Dependencies:** Lock files (package-lock.json, Cargo.lock, etc.)

### What NOT to Commit

* **Secrets:** API keys, passwords, tokens, credentials
* **Build Artifacts:** Compiled binaries, `dist/`, `build/`, `target/`
* **Dependencies:** `node_modules/`, `venv/`, `.env` files
* **IDE Files:** `.idea/`, `.vscode/` (unless project-specific settings)
* **OS Files:** `.DS_Store`, `Thumbs.db`

## 4. Git Workflow

### Feature Development

1. Create feature branch from `main` or `develop`
2. Make atomic commits with descriptive messages
3. Push branch regularly (at least daily)
4. Open Pull Request when feature is complete
5. Address review feedback with additional commits
6. Squash commits if requested during review
7. Merge via Pull Request (no direct pushes to main)

### Pull Request Process

* **Title:** Follow conventional commit format
* **Description:** Explain what, why, and how. Include screenshots for UI changes
* **Size:** Keep PRs focused and reviewable (< 400 lines when possible)
* **Tests:** Include tests for new features and bug fixes
* **Documentation:** Update documentation for user-facing changes
* **CI:** All CI checks must pass before merge

### Code Review

* **Required:** At least one approval before merge
* **Response Time:** Review within 24-48 hours
* **Feedback:** Be constructive and specific
* **Approval:** Approve only when code meets standards

### Merge Strategy

* **Squash and Merge:** Preferred for feature branches (clean history)
* **Merge Commit:** Use for important features (preserve branch context)
* **Rebase:** Use for keeping feature branches up to date (avoid merge commits)

## 5. Tagging and Releases

### Semantic Versioning

Format: `MAJOR.MINOR.PATCH` (e.g., `1.2.3`)

* **MAJOR:** Breaking changes
* **MINOR:** New features (backward compatible)
* **PATCH:** Bug fixes (backward compatible)

### Tagging

* **Format:** `v1.2.3` (prefixed with `v`)
* **Annotated Tags:** Use annotated tags for releases: `git tag -a v1.2.3 -m "Release 1.2.3"`
* **Release Notes:** Include release notes in tag message or GitHub release

### Release Process

1. Update version in code and `CHANGELOG.md`
2. Create release branch: `release/v1.2.3`
3. Final testing and bug fixes
4. Merge to `main` and tag: `git tag -a v1.2.3`
5. Push tag: `git push origin v1.2.3`
6. Create GitHub/GitLab release with notes
7. Merge back to `develop` if applicable

## 6. Git Configuration

### Required Settings

```bash
# User identification
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Default branch name
git config --global init.defaultBranch main

# Push behavior
git config --global push.default simple
git config --global push.autoSetupRemote true

# Pull behavior
git config --global pull.rebase false  # Use merge by default
```

### Recommended Settings

```bash
# Color output
git config --global color.ui auto

# Editor
git config --global core.editor "code --wait"  # VS Code
```

### Git Aliases

See [Git Aliases Reference](../../docs/reference/git-aliases.md) for the full alias catalog. Run `scripts/setup-git-aliases.sh` to install.

## 7. Git Hooks

### Pre-commit Hook

* **Linting:** Run linters (ESLint, Pylint, Clippy)
* **Formatting:** Auto-format code (Prettier, Black, rustfmt)
* **Tests:** Run fast unit tests
* **Validation:** Check commit message format

### Pre-push Hook

* **Tests:** Run full test suite
* **Type Checking:** Run type checkers (TypeScript, mypy)
* **Build:** Verify project builds successfully

### Commit-msg Hook

* **Format Validation:** Ensure commit messages follow conventional format
* **Length Check:** Validate subject line length

### Implementation

Use tools like:

* **Husky** (Node.js)
* **pre-commit** (Python)
* **git-hooks** (Rust)
* Custom shell scripts

## 8. .gitignore Patterns

### Language-Specific

**Python:**

```gitignore
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
venv/
env/
.venv
```

**Node.js:**

```gitignore
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-debug.log*
dist/
build/
```

**Rust:**

```gitignore
target/
Cargo.lock  # For libraries, not applications
```

**Java:**

```gitignore
*.class
*.jar
*.war
*.ear
.gradle/
build/
```

### Test / coverage output

Ignore generated coverage reports so they are never committed:

```gitignore
coverage/
```

Common tools that write here: Vitest, Jest, pytest, Istanbul/c8, lcov. Projects using the standards setup or install scripts get this pattern added automatically.

### General

```gitignore
# Environment
.env
.env.local
.env.*.local

# IDE
.idea/
.vscode/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Logs
*.log
logs/
```

## 9. Large Files and Git LFS

### Git LFS

Use Git LFS for:

* Binary files > 100MB
* Media files (images, videos)
* Compiled binaries
* Database dumps

### Configuration

```bash
git lfs install
git lfs track "*.psd"
git lfs track "*.zip"
```

## 10. Branch Lifecycle

### Cleanup After Merge

Branches MUST be deleted — both local and remote — immediately after their PR is merged or closed. Do not accumulate stale branches.

* **PR merge:** Enable "Automatically delete head branches" in GitHub repo settings. This handles the remote branch. Delete the local branch manually after merge.
* **Squash merges:** Squash-merged branches are not detected by `git branch --merged`. Use `git branch -d <branch>` (lowercase `-d`) which checks if the branch is fully merged; if it refuses, verify the work landed via PR, then use `git branch -D <branch>`.
* **Worktrees:** Remove the worktree before deleting its branch: `git worktree remove <path>` then `git branch -D <branch>`.

### Naming Branches for Traceability

Include enough context in the branch name to identify the work without checking the log:

```text
feat/preview-scroll-optimization    ✓ clear purpose
fix/sidebar-drag-crash              ✓ clear purpose
worktree-agent-a0939472             ✗ opaque, impossible to triage later
tmp                                 ✗ no context
copilot/sub-pr-7                    ✗ meaningless without the PR
```

Agent-generated branches MUST follow the same `type/description` convention as human branches. Opaque IDs or numeric suffixes alone are not acceptable names.

### Periodic Audit

Run a branch audit at least every two weeks (or before starting a new feature):

```bash
# List local branches not on main, sorted by last commit date
git branch --no-merged main --format='%(committerdate:short) %(refname:short)' | sort

# List remote branches with no recent activity (>14 days)
git for-each-ref --sort=committerdate --format='%(committerdate:short) %(refname:short)' refs/remotes/origin | head -20

# Delete local branches whose remote is gone
git fetch --prune
git branch -vv | grep ': gone]' | awk '{print $1}' | xargs -r git branch -D
```

Projects using `make` SHOULD include a cleanup target:

```makefile
branch-cleanup: ## Delete local branches whose remote tracking branch is gone
	@git fetch --prune
	@git branch -vv | grep ': gone]' | awk '{print $$1}' | xargs -r git branch -D
	@echo "Remaining branches:" && git branch
```

### Branch Limits

As a guideline, a repository should have fewer than **10 active branches** at any time. If you have more, audit and clean up before creating new ones. This applies to both local and remote branches (excluding `main`).

### Garbage Collection

* Run `git gc` periodically (usually automatic).
* After large cleanups, run `git gc --prune=now` to reclaim space immediately.

### Security

* **Secrets Scanning:** Use tools like `git-secrets`, `truffleHog`
* **History Rewriting:** Avoid force-pushing to shared branches
* **Access Control:** Use branch protection rules (GitHub/GitLab)

### Backup

* **Remote Repository:** Always push to remote (GitHub, GitLab, etc.)
* **Multiple Remotes:** Consider backup remote for critical projects
* **Regular Pushes:** Push at least daily during active development
