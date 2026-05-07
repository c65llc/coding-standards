---
description: Merge pending standards updates into agent configs
---

# merge-standards

Read `.standards-pending/MERGE_PLAN.md` and walk through each pending file.

For each entry:

1. Read `.standards-pending/<file>` and the existing `<file>` at the project root.
2. If the existing file is empty or missing, move the pending file into place.
3. Otherwise produce a diff and ask the user: accept new, keep existing, or merge section-by-section.
4. For any `<!-- TODO(standards): -->` markers, ask for the content (or infer from `package.json` / `Makefile`) and replace before writing.
5. Update `.standards-checksums` with the new hash.
6. Delete the pending file.

Finally, delete `.standards-pending/` if empty.
