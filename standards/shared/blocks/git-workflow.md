Conventional Commits: `type(scope): subject` — types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`.
Subject: imperative mood, ≤50 characters, no period.
Branch naming: `type/description` in kebab-case (e.g., `feature/user-authentication`, `fix/email-validation`).
One task = one branch = one PR. Work is not done until a PR exists. Prefer small, independently mergeable PRs, sequenced/stacked deliberately.
Feature branches from `main`. No direct pushes to `main`. Require one approval; all CI checks must pass.
PR merge loop: run the project's full local gate (`make ci`) first → open PR → wait for the automated reviewer → address every finding → all checks green (a partial pass is a fail) → squash-merge + delete branch. Never merge on a partial pass or before the automated review runs. The local gate must mirror CI: a check that runs in CI but not in `make ci` (or the reverse) is a bug in the gate — fix the gate, do not route around it.
Run `gh pr create` from the feature worktree (or pass `--head`); the cwd's branch is what it opens.
Worktrees live under one gitignored root, `{{WORKTREE_DIR}}/` (`worktree_dir:` in `.standards.yml`), created from the main checkout — never from inside another worktree: `git worktree add {{WORKTREE_DIR}}/<branch> -b <branch>`. Remove a worktree when its PR merges; `worktree-gc` collects merged, gone and idle (14d) ones. Build caches (`CARGO_TARGET_DIR`, pnpm store, DerivedData, Gradle, turbo) live outside the worktrees.
CI workflows on `pull_request` declare `concurrency` + `cancel-in-progress`, `timeout-minutes` on every job, and path scoping (`paths:`, or paths-filter + an always-run gate job). The changed-path → lane mapping lives in `.github/ci/routing.yml`; read it to decide which `make ci-<lane>` to run before pushing. Heavy matrices go to merge queue/nightly, not the PR lane.
Every CI step must pass on a locked, headless runner: no login keychain, no `store-credentials`, no `osascript`/`open -a`; pass secrets straight to the command or use a job-scoped keychain.
Stacked PRs: retarget dependents to `main` before merging+deleting a base branch, or the dependents get closed.
Delete branches immediately after merge. Keep fewer than 10 active branches.
Never commit: secrets, build artifacts, `node_modules/`, `.env`, IDE files, OS files.
Always commit lock files (`package-lock.json`, `Gemfile.lock`, `Cargo.lock`, `uv.lock`).
