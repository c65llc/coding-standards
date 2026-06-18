Conventional Commits: `type(scope): subject` — types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`.
Subject: imperative mood, ≤50 characters, no period.
Branch naming: `type/description` in kebab-case (e.g., `feature/user-authentication`, `fix/email-validation`).
One task = one branch = one PR. Work is not done until a PR exists. Prefer small, independently mergeable PRs, sequenced/stacked deliberately.
Feature branches from `main`. No direct pushes to `main`. Require one approval; all CI checks must pass.
PR merge loop: run the full local gate (`make ci`) first → open PR → wait for the automated reviewer → address every finding → all checks green (a partial pass is a fail) → squash-merge + delete branch. Never merge on a partial pass or before the automated review runs.
Run `gh pr create` from the feature worktree (or pass `--head`); the cwd's branch is what it opens.
Stacked PRs: retarget dependents to `main` before merging+deleting a base branch, or the dependents get closed.
Delete branches immediately after merge. Keep fewer than 10 active branches.
Never commit: secrets, build artifacts, `node_modules/`, `.env`, IDE files, OS files.
Always commit lock files (`package-lock.json`, `Gemfile.lock`, `Cargo.lock`, `uv.lock`).
