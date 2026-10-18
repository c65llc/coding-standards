---
description: Merge pending standards updates into agent configs
---

# merge-standards

Read `.standards-pending/MERGE_PLAN.md` and walk through each pending file.

For each entry:

1. Read `.standards-pending/<file>` and the existing `<file>` at the project root.
2. If the existing file is empty or missing, move the pending file into place.
3. Otherwise produce a diff and ask the user: accept new, keep existing, or merge section-by-section.
4. For any `<!-- TODO(standards): -->` markers, ask for the content (or infer from `package.json` / `Makefile`) and write it to `.standards.yml` as `project_overview: |` / `key_commands: |` blocks, so the assembler reproduces it and the checksum stays stable; then replace the markers (or re-run `./.standards/scripts/sync-standards.sh`). If setup or sync printed the YAML for sections already filled in by hand, append exactly that.
5. For a file the user wants to keep hand-curated end to end, declare `managed: { <file>: false }` in `.standards.yml` instead of merging — sync then leaves it alone and `diff-standards.sh` shows upstream changes for manual review.
6. Update `.standards-checksums` with the new hash.
7. Delete the pending file.

Finally, delete `.standards-pending/` if empty. If `doctor` fails on the post-merge hook and the project manages its own hooks, declare `hooks: custom` (or `lefthook` / `husky`) in `.standards.yml`.
