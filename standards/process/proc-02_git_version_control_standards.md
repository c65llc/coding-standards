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
* **Branch prefixes:** `feature`, `fix`, `hotfix`, `release`, `refactor`, `docs`, `test`
* **Description:** Concise, descriptive (3-5 words)

> **Branch prefixes are not commit types.** The words above name *branches*
> (`feature/user-auth`, `hotfix/security-patch`). Commit **messages** use the
> Conventional Commits types below — note `feat`, not `feature`, and there is no
> `hotfix`/`release` commit type. The canonical commit-type set is defined once
> in `shared/core-standards.md` (§ Commit Messages); this document must stay
> aligned with it.

## 2. Commit Messages

### Conventional Commits Format

```text
<type>(<scope>): <subject>

<body>

<footer>
```

### Commit Types

The canonical cross-cutting set (from `shared/core-standards.md`) is:
`feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`.

* **feat:** New feature
* **fix:** Bug fix
* **refactor:** Code refactoring (no functional changes)
* **test:** Adding or updating tests
* **docs:** Documentation changes
* **chore:** Maintenance tasks (dependencies, build config)
* **perf:** Performance improvements
* **ci:** CI/CD changes

Additional Conventional Commits types the linter also accepts
(`scripts/lint-checks/common/conventional-commits.sh`) but which fall outside
the canonical set: `build` (build-system changes), `style` (formatting-only
changes), `revert` (reverting a prior commit). Prefer the canonical types.

### Commit Guidelines

* **Subject:** Imperative mood, 50 characters or less, no period
* **Body:** Explain "what" and "why", wrap at 72 characters
* **Footer:** Reference issues/PRs: `Closes #123`, `Fixes #456`
* **Scope:** Optional, indicates area of change (e.g., `domain`, `api`, `ui`)

### Scope Allow-List

Scopes drift when every author invents their own (`edit/macos`, `editor/windows`
and `windows/edit` coexisting in one history). Projects SHOULD pin the accepted
scopes in `.standards.yml`:

```yaml
commits:
  scopes: [api, domain, ui, infra]
```

When the list is present, every *scoped* commit must use one of the listed
scopes; unscoped commits (`fix: ...`) remain allowed. The linter module, the
commit-msg hook templates and the PR-title check all read this one list.

### Pull Request Titles Are Commits

With **squash and merge** (the preferred strategy, § 4) GitHub writes the **PR
title** — not the branch commits — as the commit subject on the mainline. A
perfectly conventional branch squashed under a prose title ("Phase 1: repository
scaffold") still lands a non-conventional commit in `main`, and a commit-msg
hook never sees it.

* PR titles MUST follow the same `<type>(<scope>): <subject>` format.
* The `standards-review` composite action checks the title on every PR and
  fails the check by default (`pr-title-check: warn` downgrades it to an
  annotation, `off` disables it).
* Validate a candidate title locally with
  `.standards/scripts/check-commit-message.sh "feat(api): add endpoint"`.

### Automated Enforcement

`scripts/lint-checks/common/conventional-commits.sh` (run by `lint-standards.sh`)
inspects the last **50** non-merge commits by default. Tune the range in
`.standards.yml`:

```yaml
commits:
  window: 100          # inspect the last N non-merge commits
  since: origin/main   # or: inspect <ref>..HEAD (wins over window)
```

The module also accepts `--since <ref>` / `--window <n>` flags, and the
standards-review action defaults the range to the PR base so a PR is judged on
its own commits (that PR range beats a configured `window`; only `since` or an
explicit flag overrides it). Merge commits, `fixup!`/`squash!` prefixes and `git revert`
subjects are exempt.

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
* **Size:** Keep PRs focused and reviewable (< 400 lines when possible). When a
  task cannot fit, stack it (§ 11) instead of growing one PR
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
* **Every released changelog heading is a tag.** A `CHANGELOG.md` that lists
  0.1.4 and 0.1.5 while only `v0.1.2`/`v0.1.3` exist — and `package.json` still
  says 0.1.3 — is a release process that stopped at the prose: nothing is
  reproducible from the "released" versions. The tag step is part of the release
  job; a release workflow that publishes an artifact without running `git tag`
  is the same defect from the other side.
* **Enforcement:** `scripts/lint-checks/common/changelog-tags.sh` (in
  `make lint-standards` and the standards-review action) reads every released
  `## [x.y.z]` heading and fails when one has no `v<version>` (or `<version>`)
  tag — except the single topmost (newest) heading while every other one is tagged,
  which is a release in flight (the release PR adds the heading, the tag
  follows the merge) and warns instead; it warns
  when the root `package.json` / `Cargo.toml` / `pyproject.toml`
  version is not the latest release, and when a shallow CI clone cannot see a
  heading's tag (use `fetch-depth: 0` or `fetch-tags: true`; a `--depth` clone
  only carries the tags inside the fetched history, so that case is
  unverifiable rather than a failure — unless the tag namespace is complete,
  which the check confirms against the remote). Declare `release.changelog` and
  `release.tag_prefix` in `.standards.yml` when the file or the prefix differ.

### Release Process

1. Update version in code and `CHANGELOG.md`
2. Create release branch: `release/v1.2.3`
3. Final testing and bug fixes
4. Merge to `main` and tag: `git tag -a v1.2.3`
5. Push tag: `git push origin v1.2.3`
6. Create GitHub/GitLab release with notes
7. Merge back to `develop` if applicable

### Release Version vs. Build Version

For products that deploy continuously, distinguish two version numbers:

* **Release version** — manual semantic version (`MAJOR.MINOR.PATCH`), bumped
  deliberately at a release. It is what users see and what gates a coordinated
  release (e.g. apps and marketing site move together on a release-version bump).
* **Build version** — derived automatically and ticking on every commit to the
  mainline (e.g. `git rev-list --count HEAD`). Useful for "exact build" reporting
  and crash triage, never for user-facing semver decisions.

Surface both in an About/diagnostics view. A value only tree-shakes in if it is
actually *rendered* — exporting it isn't enough.

### Deploy Channels & Promotion

* Separate **staging/preview** from **production** by channel. The mainline
  branch auto-deploys to the staging channel; production is gated on an explicit
  promotion. **Never deploy production off arbitrary feature branches.**
* If the deploy platform's branch control takes no wildcard, gate production on a
  single long-lived `release` branch (not `release/*`) and promote by
  fast-forwarding mainline into it (`git push origin main:release`).
* Channel-gate not-yet-released content (e.g. an "unreleased" changelog section
  visible only on the staging channel) via a build-time channel variable. Verify
  the variable name matches what the deploy platform actually injects — a typo
  (`PUBLIC_CHANNEL` vs `VITE_CHANNEL`) silently ships the wrong content.
* **A green release does not prove production updated.** End the release with an
  automated version assertion against the *live* deployment (fetch it, assert the
  new release/build number), not "the promote step succeeded". The deploy
  platform's credentials and branch protections live outside the repo and fail
  invisibly — a rolled or deleted build token, or a force-push-protected `release`
  branch that silently rejects the fast-forward promote — so a green in-repo
  pipeline is necessary but not sufficient. See
  [arch-08_ci_cd_pipeline_standards.md](../architecture/arch-08_ci_cd_pipeline_standards.md)
  §7 for the CI-side smoke check.

### Scripted, Reviewable Release Cut

Automate the release cut as a **script that produces a reviewable PR**, not a
manual sequence of edits:

* A pure script performs the semver bump and promotes changelog entries
  (`unreleased/` → the released version section), and emits the release-notes body.
* The script opens (or prepares) a PR for human review before anything is tagged
  or promoted. Tagging and channel promotion happen only after that PR merges.
* Mind CI-identity loop-prevention: a PR opened by a CI token often does **not**
  trigger the normal PR gate, so a fully hands-free release usually needs a
  dedicated app token or a human to open/merge the cut PR. Document which model
  the repo uses.

See [arch-08_ci_cd_pipeline_standards.md](../architecture/arch-08_ci_cd_pipeline_standards.md)
§7 for the CI side of channel promotion.

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
* **lefthook** (any stack; single binary)
* **pre-commit** (Python)
* **git-hooks** (Rust)
* Custom shell scripts

### Conventional Commits Hook Templates

The standards repo ships ready-made commit-msg hooks that call
`scripts/check-commit-message.sh` (format + `commits.scopes` allow-list).
`setup.sh` prints the install commands but never installs a hook manager for
you:

```bash
# husky (v9+)
npx husky init   # once, if .husky/ does not exist yet
cp .standards/templates/husky-commit-msg.example .husky/commit-msg
chmod +x .husky/commit-msg

# lefthook
cp .standards/templates/lefthook.yml.example lefthook.yml   # or merge the blocks into yours
lefthook install
```

`make doctor` recognises `lefthook.yml` and `.husky/` as hook managers and
warns when neither defines a commit-msg hook. Because both managers take over
`core.hooksPath`, the native `.git/hooks/post-merge` reminder that `setup.sh`
writes stops running; the lefthook template restores it with a `post-merge`
block and doctor warns when a husky project lacks one.

Hooks guard *branch* commits only — pair them with the PR-title check (§ 2,
"Pull Request Titles Are Commits") to protect squash-merged history.

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

## 11. Stacked PRs (gh-stack)

The default unit of work is *one task = one branch = one PR*. When a task is too
large to review as a single PR, the unit becomes **one task = one stack of
focused PRs**: an ordered chain of branches in which each layer targets the one
below it and the bottom targets the trunk (`main`). GitHub's stacked pull
requests — driven locally by the official
[`gh stack`](https://docs.github.com/en/pull-requests/how-tos/stacked-pull-requests)
CLI extension — are the preferred way to do this. Each PR shows only its own
layer's diff, the layers are linked as a stack in the PR UI, and GitHub rebases
and retargets the remaining layers as the bottom merges.

### When to stack

Stack when **any** of these holds — and split a single PR into a stack rather
than growing it:

* **Size.** The diff would exceed the PR-size smell threshold in § 4 (~400
  changed lines, not counting generated files and lockfiles), or it touches more
  than ~15 files a reviewer has to read rather than skim.
* **Dependency depth.** The change is an ordered chain (schema → domain → API →
  UI; standard → linter → docs → agent config) whose lower layers are reviewable
  on their own.
* **Separable review.** Different reviewers or CODEOWNERS own different parts, or
  a risky part (a migration, a security-sensitive path) deserves its own scrutiny
  instead of hiding inside a feature diff.
* **Test governance.** One small part would pull disproportionate slow lanes from
  the routing table ([proc-05 § 5](./proc-05_test_governance.md)); isolating it
  in its own layer keeps the PR evidence (proc-05 § 8) attributable to the code it
  covers.

Do **not** stack when:

* The change fits one focused PR under the threshold — a stack of one is a PR.
* The layers would not be independently meaningful. A layer that only compiles
  once the next one lands is not a layer.
* The parts are trivially coupled and must land together to keep `main` green.
  Stacks merge layer by layer, and every layer must leave `main` working.

Decide to stack at planning time ([proc-01 § 11](./proc-01_documentation_standards.md#11-spec-plan-design-pass-and-verification-documents),
[proc-04 § 8](./proc-04_agent_workflow_standards.md)), not after an oversized PR
is open — though splitting an open oversized PR into a stack is allowed, and
preferred over "review it in sections".

### Layer rules

Every layer is a complete PR in its own right:

* **Stands alone.** With the layers below it as its base, the layer builds, its
  tests pass and coverage holds (≥ 95 % in modified modules,
  [proc-03 § 2](./proc-03_code_review_expectations.md)). No "will fix in the
  next layer".
* **One concern per layer.** A layer is one architectural slice or one logical
  step, and its tests ride in the same layer as the code they cover. A refactor
  that enables the feature is its own lower layer (proc-03 § 9, Refactoring PRs).
* **Named for traceability.** `<type>/<task>/<NN>-<layer>`, e.g.
  `feat/user-export/01-schema`, `feat/user-export/02-api`,
  `feat/user-export/03-ui`. The shared `<task>` segment groups the stack in
  `git branch` output and the two-digit prefix sorts layers in order. The
  `type/description` rule from § 1 and § 10 still applies — no opaque IDs.
* **Conventional title per layer.** Each PR title is its own
  `<type>(<scope>): <subject>`: under squash-and-merge it becomes that layer's
  commit subject on `main` (§ 2, "Pull Request Titles Are Commits"). Never keep
  an auto-generated title (`gh stack submit --auto`) without rewriting it.
* **Stack position in the body.** Every layer's PR body states its position and
  the chain: `Stack: 2 of 3 — #41 → #42 (this PR) → #43`. The bottom layer
  carries `Closes #N`; the layers above carry `Part of #N`, so the issue closes
  once, when the bottom lands (see § 12, one close-keyword per line).

### Install

```bash
gh extension install github/gh-stack   # needs gh >= 2.0 and git >= 2.36
gh extension upgrade stack             # keep it current
gh skill install github/gh-stack       # optional: the gh-stack agent skill
```

`gh stack` is the local workflow; the stack itself is a GitHub object.
Contributors without the extension can still review, approve and merge layers
in the web UI, and hand-chained PRs can be linked into a stack with
`gh stack link <branch-or-pr>...` or from the GitHub website.

### Create a stack

Work from one worktree for the whole stack (proc-04 § 8):

```bash
git worktree add .claude/worktrees/feat-user-export -b feat/user-export/01-schema
cd .claude/worktrees/feat-user-export
gh stack init feat/user-export/01-schema   # trunk = default branch; --base <branch> overrides
# ... commits for the schema layer ...
gh stack add feat/user-export/02-api       # new branch on top of the current top
# ... commits for the API layer ...
gh stack add feat/user-export/03-ui
# ... commits for the UI layer ...
gh stack view                              # order, PR links, last commit per layer
gh stack submit                            # push every branch, one PR per layer, linked as a stack
```

`submit` opens an editor for every title and body — write the Conventional
Commit title and the stack-position line there. Each PR's base is the branch
below it, so reviewers see only that layer. `gh stack push` pushes the branches
without touching PRs; `gh stack sync` fetches, fast-forwards the trunk, cascades
the rebase, pushes with `--force-with-lease` and refreshes PR state in one step.

### Update a stack

Fix a layer in the layer that owns the change, then cascade:

```bash
gh stack checkout feat/user-export/01-schema   # or: gh stack down / up / bottom / top
# ... fix, commit ...
gh stack rebase                                # fetch trunk, replay every layer above onto the fix
gh stack push                                  # --force-with-lease per branch
```

* After `main` moves, `gh stack rebase` (or `gh stack sync`) rebases the bottom
  onto the new trunk and cascades. GitHub shows a **Rebase stack** button when a
  stack goes non-linear; either path works. GitHub keeps approvals on a layer
  whose diff did not change across the rebase, even with "dismiss stale
  approvals" on.
* A conflict pauses the rebase in the conflicted layer: resolve, `git add`, then
  `gh stack rebase --continue` (or `--abort` to restore every branch). `init`
  enables `git rerere`, so a resolution replays on the next cascade.
* Restructure — reorder, fold, insert, rename or drop layers — with
  `gh stack modify`, then `gh stack submit` to re-sync the PRs. Do it before
  review starts, not under a reviewer.
* **Once a layer has a reviewer, append, don't rewrite** (proc-03 § 9,
  proc-04 § 8): add commits; the cascade rebase is the only history rewrite the
  reviewer should see.

### Merge a stack

Stacks merge **bottom-up**, and every layer must satisfy the trunk's protection
rules — required checks, required reviews, CODEOWNERS — as if it targeted `main`
directly:

```bash
gh stack merge --squash              # pick how far up to merge from the lowest unmerged layer
gh stack merge --squash --yes 42     # non-interactive: every unmerged layer up to and including PR #42
```

* **Squash per layer.** Squash creates one commit per layer on `main`, titled
  from that layer's PR title, so a stack of three lands as three Conventional
  Commits in order. Merge commit and rebase are also supported; squash is the
  default here (§ 4).
* **Contiguous from the bottom.** Merge the bottom layer alone, or any contiguous
  group up from the bottom, as one all-or-nothing operation. A mid-stack layer
  cannot merge without the layers below it.
* **GitHub retargets the rest.** After a merge the next unmerged layer is rebased
  to target the trunk and becomes the new bottom — no manual
  `gh pr edit --base`. The base-deletion trap in § 12 applies to dependent PRs
  that are *not* linked into a stack.
* **Merge queues** take the whole stack in order. **Auto-merge is not available
  for stacked PRs** — merge explicitly once the bottom (or a contiguous group) is
  green and reviewed.
* When the whole stack has merged, `gh stack sync --prune` deletes the merged
  local branches; then remove the worktree as in § 10.

### Review and CI per layer

* **Every layer runs the full PR gate.** Workflows on `pull_request` run for each
  PR as if it targeted the stack base, so a three-layer stack runs the gate three
  times, and required checks, reviews and CODEOWNERS are evaluated against the
  trunk for every layer.
* **Gate expensive lanes by stack position.** `github.event.pull_request.stack`
  (present only on stacked PRs) exposes `number`, `size`, `position` (1 = bottom),
  `base.ref` and `base.sha`. Keep the fast tier (proc-05 § 4) on every layer; run
  slow lanes only on the top layer
  (`stack.position == stack.size`, the full change) or the lowest unmerged layer
  (`stack.base.ref == pull_request.base.ref`, the one about to land).
* **Each layer's PR body carries its own evidence** (proc-05 § 8): the tested
  commit and the lanes that ran for *that* layer.
* **Review is per layer, bottom-up** — reviewer rules in
  [proc-03 § 9](./proc-03_code_review_expectations.md), "Reviewing a Stack".

### Worked example

Adding a language standard to this repository is one task spanning four
concerns. As a stack:

| Layer | Branch | PR title | Stands alone because |
|-------|--------|----------|----------------------|
| 1 | `feat/lang-14-nim/01-standard` | `feat(standards): add lang-14 Nim standards` | A new document; nothing consumes it yet |
| 2 | `feat/lang-14-nim/02-linter` | `feat(lint): add Nim checks to lint-standards` | The checks only fire when Nim files exist |
| 3 | `feat/lang-14-nim/03-docs` | `docs(website): publish the lang-14 Nim page` | The site builds with or without layer 4 |
| 4 | `feat/lang-14-nim/04-agent-configs` | `feat(agents): regenerate standards lists for lang-14` | Generated from layer 1; `make check-agent-configs` green |

Each layer merges green in order, and a reviewer who only owns the linter reads
layer 2.

### Without the extension

If `gh stack` is unavailable, chain the PRs by hand — each PR's base is the
branch below it, the bottom on `main` — and link them into a stack from the
GitHub website (or have a teammate run `gh stack link`). Dependent PRs that are
never linked get none of GitHub's automatic retargeting: read § 12 before
merging the bottom.

## 12. Dependent PRs and Platform Automation Traps

When PRs depend on each other without being linked into a stack, or are driven
by automation, a handful of platform behaviors silently cause lost work or false
signals. Encode them.

### Hand-chained dependent PRs — the base-deletion trap

When PR **B** is based on PR **A**'s branch (B's base = A's feature branch) and
the two are **not** linked as a GitHub stack (§ 11):

* Merging **A** with delete-branch (`gh pr merge A --squash --delete-branch`)
  **closes B** — the host does *not* auto-retarget B to mainline, and B cannot be
  reopened once its base branch is gone.
* **Avoid it:** before merging A, either retarget B to mainline first
  (`gh pr edit B --base main`) while A's branch still exists, or merge A *without*
  deleting its branch until B is retargeted.
* **Recover** (if B was already closed by an A merge): in B's worktree,
  `git rebase --onto origin/main <A-tip-commit>` to drop A's now-redundant commits
  (their content is in mainline via the squash) and replay only B's own commits,
  then open a fresh PR B′ → mainline referencing the closed one.

### A conflicting PR runs no checks

A PR with merge conflicts has no merge ref, so the host runs **none** of its
merge-ref-triggered workflows — it looks like CI never fired (zero runs created,
not even queued). If a PR's checks are entirely absent, check its mergeable state
and resolve the conflict; the checks then trigger normally. Distinguish this from
a self-hosted runner being offline (which produces a *queued* run that waits).

### Other host-automation traps

* **One close-keyword per line.** `Closes #A, #B, #C` only auto-closes the *first*
  issue. Write one `Closes #X` per line to fan out across issues.
* **Check polling can settle early.** Right after a push, only fast external checks
  are registered; host-run jobs appear seconds later. A poll that exits as soon as
  "all known checks are non-pending" can exit before real CI starts — guard with a
  minimum-expected-check count.
* **`gh pr create` infers the branch from the current directory.** Run it from the
  correct worktree, or pass `--head <branch>` explicitly, or it opens a PR for
  whatever branch the cwd is on. See
  [proc-04_agent_workflow_standards.md](./proc-04_agent_workflow_standards.md)
  § Worktree Hygiene.
