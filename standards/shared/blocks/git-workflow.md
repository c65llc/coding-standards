# Git Workflow

Conventional Commits: `type(scope): subject` — types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`.
Subject: imperative mood, ≤50 characters, no period.
Branch naming: `type/description` in kebab-case (e.g., `feature/user-authentication`, `fix/email-validation`).
One task = one branch = one PR. Work is not done until a PR exists.
Feature branches from `main`. No direct pushes to `main`. Require one approval; all CI checks must pass.
Delete branches immediately after merge. Keep fewer than 10 active branches.
Never commit: secrets, build artifacts, `node_modules/`, `.env`, IDE files, OS files.
Always commit lock files (`package-lock.json`, `Gemfile.lock`, `Cargo.lock`, `uv.lock`).
