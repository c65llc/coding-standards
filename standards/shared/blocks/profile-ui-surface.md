The platform owns the window, selection, spelling, the context menu, scrolling, focus order and the accessibility tree. The design system owns what is inside the frame. Do not reimplement what the platform draws.
No pointer cursor on rows, buttons, tabs or toolbar items; only hyperlinks in content change the cursor. Chrome text (labels, headings, button text) is not selectable.
No smooth-scroll polyfills; no route or page transitions by default; every animation honors the platform's reduced-motion setting.
Loading shows nothing under 200 ms, a spinner from 200 ms to 2 s, and progress beyond. Skeleton placeholders only where a project ruling names the surface.
Dialogs, sheets, menus, notifications and save panels use the platform primitive where one exists, never an overlay drawn in content.
Every actionable element is reachable by keyboard; focus is visible and platform-styled; Escape always does something meaningful.
Dark mode follows the system and switches without flicker; the accent follows the system accent unless a ruling says otherwise; chrome uses the system font.
Where the project keeps design rulings (a rulings ledger, platform primers under `docs/design/`), the ruling wins over the audit and the change cites it. Where no ruling and no audit item applies, say so rather than inventing.
Before claiming a UI change is done, walk the `arch-11` §3 audit items for the surface it touches on the running build. Compiling is not seeing.
Full standard: `arch-11_ui_surface_standards.md` (ownership §2, audit §3, rulings §4).
