---
name: ui-surface
description: Use before changing or reviewing any user-facing UI on web, desktop or mobile, when a UI feels web-y or feels off, before a design pass, before claiming a UI change is done, and when choosing between a platform primitive and a custom one. Do NOT use for projects that have not declared the ui-surface profile.
profiles: ui-surface
---

# UI Surface

Change, review and validate user interfaces under `arch-11` (UI Surface
Standards): the platform owns the frame, the design system owns what is inside
it, and a project's own rulings beat the generic audit. This runbook routes to
the right place; it does not restate the audit.

## When to Use

- Before changing or reviewing any user-facing UI on any surface (browser tab,
  installed PWA, native shell)
- When someone says a UI "feels web-y" or "feels off" and cannot say why
- Before a design pass, and before claiming a UI change is done
- When choosing between a platform primitive (sheet, dialog, menu, scrollbar,
  notification, save panel) and a custom one
- When the `web-tells` lint check reports a hit

## Workflow

1. **Find the project's ruling before touching code.** Look for a rulings
   ledger and platform primers under `docs/design/`, or wherever the project's
   agent guide points. If there is a row for the pattern, that is the answer:
   follow it and cite it in the change. If the ledger has a "proposed" or
   "retired" section, read what it means before proceeding. A ruling beats any
   audit item below.
2. **Identify the surface class** (`arch-11` §1) and read its ownership table
   (§2). The question to ask of every detail is: what does the equivalent
   platform control do here? Do exactly that.
3. **Pick the audit items in scope** (`arch-11` §3): the five to ten items in the
   surface area of the change, tagged for the surface class. For a "feels off"
   report, walk the whole list with the reporter; for a refactor, walk it all.
4. **Check them on the running build**, not the source. Compiling is not
   seeing: a wrong cursor, a clipped label and a glyph drawn in the wrong colour
   pass every headless gate.
5. **Before "done"**, record each in-scope item as observed, failed or not
   applicable. A failed item is fixed in this change or filed with its reason.
6. **When no ruling and no audit item applies, say so.** Do not invent a
   pattern quietly: propose a stub row for the project's ledger (if it keeps
   one) and build behind it.
7. **A `web-tells` hit** is either a deliberate exception, recorded in the
   committed `.standards-ui-allow`, or a fix. Never silence the whole check.

## Output style

- Cite the audit item by number (`arch-11` §3 item 24) and the ownership table
  row, not the whole standard.
- Cite the project ruling's file and row when one applies, and say plainly when
  none does.
- Name what each recommendation gives up (`arch-07` T10 applies here too).
- Report the audit as item → result so the next reviewer can re-check it.
