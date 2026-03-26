---
title: "Preview Before You Commit: --dry-run and make diff-standards"
date: 2026-03-25
authors:
  - name: C65 LLC
---

Phase 4 of the standards tooling roadmap adds two preview capabilities that let you see exactly what `setup` and `sync-standards` would change before a single file is modified.

## The problem: trust during team rollouts

When you run `make setup` or `make sync-standards` in an existing project, files get written. For a solo developer that is usually fine, but for a team rollout — or any project with carefully tuned AI agent configs — you want to review changes before committing to them. The new `--dry-run` flag and `make diff-standards` target solve this.

## --dry-run for setup and sync

Both `scripts/setup.sh` and `scripts/sync-standards.sh` now accept a `--dry-run` flag. When active, no files are created, modified, or deleted. Instead, each write operation prints a `[dry-run]` line describing what would have happened.

```
$ ./scripts/setup.sh --dry-run

🔍 DRY RUN — showing what would change (no files modified)

📝 Assembling claude-code config...
  [dry-run] Would write: /project/CLAUDE.md
✅ claude-code config (dry-run)
📝 Assembling cursor config...
  [dry-run] Would write: /project/.cursorrules
✅ cursor config (dry-run)
  [dry-run] Would write: /project/.standards.yml
  [dry-run] Would write: /project/.git/hooks/post-merge
  [dry-run] Would append to: /project/.gitignore
```

Nothing was written. You can now review the list and decide whether to proceed.

The same flag works for sync:

```
$ ./scripts/sync-standards.sh --dry-run

🔍 DRY RUN — showing what would change (no files modified)

  [dry-run] Would pull latest standards (submodule has updates)
  [dry-run] Would re-assemble: /project/CLAUDE.md
  [dry-run] Would re-assemble: /project/.cursorrules
  [dry-run] Would create: /project/.gemini/GEMINI.md
```

## make diff-standards: line-level preview

`--dry-run` tells you which files would change. `make diff-standards` tells you exactly what would change inside each file. It assembles every declared agent config to a temp file, diffs it against the installed version, and prints color-coded output.

```
$ make diff-standards

Standards Diff
=======================================

→ claude-code  (CLAUDE.md)
  ~ Changes: +12/-3 lines
--- CLAUDE.md
+++ (assembled)
@@ -45,7 +45,7 @@
...

→ cursor  (.cursorrules)
  ✅ Up to date

→ copilot  (copilot-instructions.md)
  + Would create: .github/copilot-instructions.md

=======================================
  Summary: 1 up to date  1 would change  1 new

Run make sync-standards to apply changes.
```

No temp files are left behind. If everything is up to date you see only checkmarks.

## Recommended workflow for team rollouts

1. `make diff-standards` — review what would change across all agents
2. `./scripts/sync-standards.sh --dry-run` — confirm the list of write operations
3. `make sync-standards` — apply once you are satisfied
4. Commit the updated agent configs in a single PR for team review

This workflow is especially useful when pulling a new version of the standards submodule: diff first, sync second, never surprise your teammates.
