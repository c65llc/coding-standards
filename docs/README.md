# Documentation Index

Every document under `docs/` with its status, per
[proc-01 §9](../standards/process/proc-01_documentation_standards.md): `live`
documents describe current behaviour and are edited in the PR that changes it;
`historical` documents are point-in-time records (implemented specs, finished
plans, verification docs) and are never rewritten. Add a row in the PR that
creates a document; flip a row to `historical` in the PR that implements or
retires it.

## Getting started and guides

| Document | Status | Notes |
|----------|--------|-------|
| [getting-started/installation.md](getting-started/installation.md) | live | Install via `install.sh`, submodule or clone |
| [getting-started/quick-start.md](getting-started/quick-start.md) | live | First ten minutes with the standards |
| [getting-started/how-it-works.md](getting-started/how-it-works.md) | live | Setup, sync and agent-config assembly |
| [getting-started/project-structure.md](getting-started/project-structure.md) | live | Repository layout |
| [guides/ci-cd-integration.md](guides/ci-cd-integration.md) | live | Standards-review action and CI gates |
| [guides/customization.md](guides/customization.md) | live | Project-specific overrides and `.standards.yml` |
| [guides/multi-agent-setup.md](guides/multi-agent-setup.md) | live | Running several AI agents against one config |
| [guides/cursor-commands.md](guides/cursor-commands.md) | live | Cursor slash commands shipped by setup |
| [PROJECT_SETUP_EXAMPLE.md](PROJECT_SETUP_EXAMPLE.md) | live | End-to-end walkthrough of a new project |

## Reference

| Document | Status | Notes |
|----------|--------|-------|
| [reference/scripts.md](reference/scripts.md) | live | Every script under `scripts/` |
| [reference/makefile-targets.md](reference/makefile-targets.md) | live | `make` targets |
| [reference/agent-configs.md](reference/agent-configs.md) | live | Generated agent config files |
| [reference/git-aliases.md](reference/git-aliases.md) | live | Aliases installed by `setup-git-aliases.sh` |
| [reference/merge-standards-prompt.md](reference/merge-standards-prompt.md) | live | The `/merge-standards` handoff prompt |
| [TOOLING.md](TOOLING.md) | live | GitHub project lifecycle automation |
| [GH_TASK_GUIDE.md](GH_TASK_GUIDE.md) | live | `gh-task` CLI guide |
| [GH_TASK_QUICKSTART.md](GH_TASK_QUICKSTART.md) | live | `gh-task` quick start |
| [deploy.md](deploy.md) | live | Docs-site deployment on Cloudflare Pages |
| [changelog.md](changelog.md) | live | Release notes (append-only) |

## Decisions

| Document | Status | Notes |
|----------|--------|-------|
| [adr/0001-unified-standards-repository.md](adr/0001-unified-standards-repository.md) | live | Accepted; live until superseded |

## Specs, plans and design records

| Document | Status | Notes |
|----------|--------|-------|
| [plans/2026-03-02-public-launch-design.md](plans/2026-03-02-public-launch-design.md) | historical | Implemented |
| [plans/2026-03-02-public-launch-plan.md](plans/2026-03-02-public-launch-plan.md) | historical | Done |
| [plans/2026-03-03-security-standards-design.md](plans/2026-03-03-security-standards-design.md) | historical | Implemented as sec-01 |
| [plans/2026-03-03-security-standards-plan.md](plans/2026-03-03-security-standards-plan.md) | historical | Done |
| [superpowers/specs/2026-03-25-smart-sync-merge-design.md](superpowers/specs/2026-03-25-smart-sync-merge-design.md) | historical | Implemented (1.2 safe setup) |
| [superpowers/specs/2026-03-25-token-efficiency-agent-best-practices-design.md](superpowers/specs/2026-03-25-token-efficiency-agent-best-practices-design.md) | historical | Implemented |
| [superpowers/plans/2026-03-25-smart-sync-merge-plan.md](superpowers/plans/2026-03-25-smart-sync-merge-plan.md) | historical | Done |
| [superpowers/plans/2026-03-25-token-efficiency-agent-best-practices-plan.md](superpowers/plans/2026-03-25-token-efficiency-agent-best-practices-plan.md) | historical | Done |
| [superpowers/plans/2026-04-16-1.2-safe-setup.md](superpowers/plans/2026-04-16-1.2-safe-setup.md) | historical | Done |
| [doc-lint-verification.md](doc-lint-verification.md) | historical | Verification record for PR #208 (doc-lint, document templates) |
