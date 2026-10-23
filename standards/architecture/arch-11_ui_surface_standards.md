# UI Surface Standards

These standards govern what makes a user interface read as **an app on this
platform** rather than **a web page in a frame**. They apply to any project that
ships a UI to people on a desktop or mobile platform, including a web app
installed as a Progressive Web App (PWA). They are independent of
[arch-07](./arch-07_cross_platform_shared_core_standards.md): a single-platform
web app opts in to this standard alone; a shared-core product opts in to both.

The judgement this standard encodes is cheap and unforgiving. A person fluent in
their platform looks at an interface for thirty seconds and either stops
noticing it or says "this feels off." What they noticed is almost always one of
the items in §3, and almost always a five-minute fix once named.

## 1. Scope and surface classes

Three surface classes, each with a different line between what the platform owns
and what the product owns:

| Class | What it is | Where the frame comes from |
|-------|------------|----------------------------|
| **Browser tab** | A web app opened in a browser | The browser: tabs, address bar, scrollbars, find, zoom |
| **Installed PWA** | A web app installed to the desktop or home screen, often with a custom title bar (window-controls overlay) and standalone display | The OS window, with the app drawing most of the chrome |
| **Native shell** | A platform toolkit app (SwiftUI/AppKit, Compose, WinUI, Flutter) | The OS window and the toolkit's controls |

An installed PWA is the class most often mistaken for the easy one: it looks
like a window, so every browser idiom it carries (pointer cursors, selectable
labels, route fades, DOM dialogs) is suddenly visible against the platform's own
apps beside it.

## 2. Who owns what

The platform draws its own blur, scrollbar, focus ring, selection and context
menu better than the product can, and it does so consistently with every other
app the person uses. Reimplementing any of them is slower, less correct, more
brittle across OS updates, and the person notices. The product's job is what is
**inside** the frame.

**Browser tab**

| The platform owns | The design system owns |
|-------------------|------------------------|
| Focus order, `:focus-visible`, the accessibility tree | What focus looks like and where it sits |
| Pointer and coarse-pointer media queries | What changes between them |
| Scrolling, overscroll, text selection in content | One scroll owner per region; which regions are content |
| `prefers-color-scheme`, `prefers-reduced-motion` | Both appearances, drawn in full; what motion remains |
| Find, zoom, print, the address bar | Nothing: do not fight them |

**Installed PWA**

| The platform owns | The design system owns |
|-------------------|------------------------|
| The window, its shadow, corner radius and controls | The title-bar region's contents when window-controls overlay is in use, and that it is draggable end to end |
| Standalone display mode, the theme colour of the chrome | Declaring them (`display`, `theme-color`), both appearances |
| Everything in the browser-tab row above | Everything in the browser-tab row above |
| Native notifications, file handling, share targets | Registering for them and handling them without a web-style fallback dialog |

**Native shell**

| The platform owns | The design system owns |
|-------------------|------------------------|
| The window frame, traffic lights or caption buttons, full-screen transitions | Everything inside the frame |
| Menus as a mount; sheets, popovers, dialogs, the services and share menus | The menu catalogue; the interiors of sheets and popovers |
| Text selection, spelling, dictation, the context menu, input methods | Which views are editable |
| Appearance (light/dark, increased contrast), system accent, system font | Both ramps of every pattern; whether to follow the accent |
| Scrolling physics, overlay scrollbars, rubber-banding | Nothing: do not fight them |

The unifying rule: ask **what the equivalent platform control does here** and do
exactly that. The error is not "too much" or "too little" of any effect; it is
*uniform* treatment where the platform varies by control kind.

## 3. The audit

Each item is one observable behaviour, tagged by the surface classes it applies
to: **[web]** (browser tab and installed PWA), **[native]** (native shell),
**[both]**. Score each item on the running app. Most products fail five to ten
items on first pass; each is cheap once named.

### Input and cursor

* **1** **[web]** No `cursor: pointer` on rows, tabs, toolbar items or buttons. Native
   lists and buttons do not change the cursor; only hyperlinks in content do.
* **2** **[web]** Chrome text (labels, headings, button text, sidebar rows) is not
   selectable. Only content is.
* **3** **[both]** The I-beam cursor appears over editable text only.
* **4** **[both]** The context menu is the platform's, or the product's own menu of
   real actions; never the browser's default.
* **5** **[web]** No link preview, force-touch or long-press callout on chrome.
* **6** **[web]** No spellcheck underline on chrome; only in editable text.
* **7** **[both]** Input methods compose at the caret. Test with at least one CJK
   input method.
* **8** **[both]** A pressed state exists and is distinct from hover.
* **9** **[both]** Hover varies by control kind the way the platform's does: a subtle
   background on list rows and borderless toolbar buttons, none on plain push
   buttons, an underline on content links only.

### Windowing and focus

* **10** **[native]** The platform's close, minimise and zoom shortcuts work.
* **11** **[native]** Zoom sizes the window to its content; full screen is a separate
  explicit action.
* **12** **[both]** The window remembers size and position across launches, per
  screen when there are several.
* **13** **[both]** Activating the app from the dock, taskbar or launcher brings back
  the last window; it does not open a new one unless the product's identity
  demands it.
* **14** **[both]** Settings open in their own window or the platform's settings
  surface, with the platform's shortcut.
* **15** **[both]** Confirmations and alerts are the platform's dialogs or sheets,
  never a DOM overlay with a backdrop blur.
* **16** **[web]** In an installed PWA with a window-controls overlay, the whole
  title-bar region drags the window, not only a handle in the middle.
* **17** **[web]** The installed PWA declares standalone display and a theme colour
  for both appearances, so its chrome matches the OS window beside it.
* **18** **[both]** Losing focus behaves predictably for the product's kind (a
  launcher hides; a document window stays).

### Materials and visual

* **19** **[native]** The window background is the platform material.
* **20** **[both]** Dark mode follows the system and switches without a flash or a
  partial repaint.
* **21** **[both]** The accent colour follows the system accent unless a design
  ruling says otherwise, and the ruling says why.
* **22** **[both]** Chrome uses the system font; a brand font is reserved for content
  where a ruling places it.
* **23** **[web]** No `box-shadow` or `border-radius` on the window itself; the OS
  draws the window.
* **24** **[web]** No skeleton placeholders for operations under 500 ms unless a
  project ruling adopts them for a named surface.
* **25** **[both]** Empty states are terse: an icon and a line, not a paragraph.
* **26** **[both]** No onboarding tour by default; the interface explains itself, and
  a first-use hint appears once.

### Scrolling

* **27** **[both]** Scrollbars are the platform's: overlay and fading where the OS does
  that, thin where the OS does that, classic where the person opted out.
* **28** **[web]** No smooth-scroll polyfill; programmatic scrolls use the platform's
  default behaviour unless a ruling names the exception.
* **29** **[both]** No custom rubber-band or scroll-to-top override.
* **30** **[both]** Scroll position is preserved across navigation within a window.
* **31** **[both]** Exactly one scroll owner per region; nested scrollers are a
  ruling, not an accident.

### Motion

* **32** **[web]** No route or page transitions by default; native apps cut between
  views.
* **33** **[both]** Every animation honours the platform's reduced-motion setting.
* **34** **[both]** Window resize is animated by the OS, not by layout animation in
  the app.
* **35** **[both]** No spring or bounce on simple state changes; spring is reserved
  for grab-and-drag.
* **36** **[both]** Loading: nothing under 200 ms; a spinner from 200 ms to 2 s;
  progress beyond 2 s.

### Keyboard

* **37** **[both]** Every actionable element is reachable by keyboard; tab order is
  logical, not DOM order where those differ.
* **38** **[both]** Focus rings are visible and platform-styled.
* **39** **[both]** Menu and command shortcuts use the platform's modifier
  conventions.
* **40** **[both]** Escape always does something meaningful: close the popover,
  cancel, dismiss.
* **41** **[both]** Type-ahead works in lists.
* **42** **[both]** A text field's standard editing shortcuts (select all, word
  movement, undo) are the platform's.

### Loading and state

* **43** **[both]** The wrong document is never shown after an open action; a
  stand-in or nothing, never stale content.
* **44** **[both]** A late response never overwrites newer state.
* **45** **[both]** Network timeouts surface as a user-visible error within ten
  seconds, with the next step in the copy.
* **46** **[both]** Save state is visible where the product's ruling places it, and
  nowhere else.
* **47** **[both]** An action's result is acknowledged within one frame by structure
  (selection, a minted tab) even when its content is still arriving.

### System integration

* **48** **[both]** URL schemes are registered and work system-wide.
* **49** **[both]** File associations work; opening an associated file opens the app
  on it.
* **50** **[both]** Drag and drop carries real file URLs the file manager accepts.
* **51** **[both]** Copy writes every pasteboard type the content warrants: plain
  text, rich text, HTML.
* **52** **[both]** Save and open use the platform's panels, never a download bar.
* **53** **[both]** Notifications go through the platform's notification centre, never
  a toast drawn in content for system-level events.
* **54** **[native]** Updates are real (a signed updater or the store), never a
  "download the new version" link.
* **55** **[both]** Crashes reach a crash reporter with symbolicated stacks.
* **56** **[native]** A second launch focuses the existing instance where the platform
  does not already guarantee it.
* **57** **[native]** The bundle or manifest is complete: identifier, version, icon,
  document types.
* **58** **[web]** The installed PWA registers file handlers and share targets it
  supports, and handles them without falling back to a web-style dialog.

### Accessibility

* **59** **[both]** The platform screen reader can navigate the entire interface.
* **60** **[both]** Focus changes are announced.
* **61** **[both]** Colour contrast meets WCAG AA in both appearances.
* **62** **[both]** Layout survives the largest system text size; no fixed-pixel
  heights that clip.
* **63** **[both]** No status is conveyed by colour alone.
* **64** **[both]** Touch targets meet the platform floor on touch surfaces; the
  floor is not imported onto pointer surfaces where it does not apply.

### Parity

* **65** **[both]** Every shipping surface has the same feature set, or the gap is
  written down with its reason.
* **66** **[both]** A visual difference between surfaces matches a platform
  convention, not an accident of who built which one.
* **67** **[both]** A pattern that exists on one surface and is absent on another is a
  decision on record (§4), never a blank.

## 4. Project rulings beat the audit

The audit is generic. A product accumulates decisions that are better than
generic: where its save state lives, which surface adopts a skeleton and why,
what its ghost row at the end of a list does. Where a project keeps such
rulings, **the ruling wins over any audit item and the change cites it.**

This standard does not mandate the files, but it names the shape that has held
up, so a project that adopts it adopts something known to work:

* **A rulings ledger.** One file, one row per UI pattern: the ruling, what it
  replaced (cite the pass or review, not a commit), the surfaces it applies to
  (where "not on this surface" is legitimate and blank is not), and the
  **assertion** that holds it. A ruling that can only be checked by launching a
  window is a ruling nobody checks. Amend a row; never add a second row for the
  same pattern. The moment the ledger becomes a directory it stops being the
  thing read before work starts.
* **Platform primers.** One file per surface: a translation table (what each
  ruled pattern becomes on that surface, which platform primitive hosts it,
  which floors apply) and a list of what has already gone wrong there. **A primer
  line enters only by discharging a shipped defect**, with what was written, what
  it should have been, the reference that proves it, and the mechanism in one
  clause. A line whose reason is a preference belongs in a review comment, not a
  primer.
* **A defect record** per UI disagreement, filed against a root-cause class, that
  **owes** one of: a gate, a primer line, an assertion, or a ledger amendment
  before it closes. A loop that stops at "fixed" is the loop that re-finds the
  same defect next quarter.

Suggested location: `docs/design/`. An agent working under the `ui-surface`
profile looks there (or wherever the project's agent guide points) **before**
touching code, finds the row, and follows it; where there is no row and no audit
item, it says so rather than inventing.

## 5. Review usage

* **A PR that touches UI:** pick the five to ten audit items in its surface area
  and check them explicitly on the running build. Compiling is not seeing: a
  rendered glyph, a clipped label and a wrong cursor pass every headless gate.
* **A "feels off" report:** walk §3 with the reporter. The item they could not
  name lands when they see it written down.
* **A refactor:** walk the whole list. Refactors silently undo feel work.
* **Code review grep (web):** `cursor: pointer`, `user-select: text` outside
  editable regions, `scroll-behavior: smooth`, `behavior: 'smooth'`, custom modal
  overlays, hard-coded accent colours. The `ui-surface` profile's `web-tells`
  check reports the first four as warnings; a committed `.standards-ui-allow`
  records the deliberate ones.

## 6. Output style for agents

An agent advising under this standard:

* cites the audit item by number (`arch-11 §3 item 24`) or the tenet by short name
  (`arch-07 T8 — adopt the platform`), never the whole standard;
* cites the file and section of a project ruling when one applies, and says
  plainly when none does;
* names what each recommendation gives up — there are no free wins in this
  standard, only trades;
* prefers "what does the equivalent platform control do here" to any general
  rule when the two disagree.

## 7. Sources

* yetone, *native-feel-skill* (MIT) —
  <https://github.com/yetone/native-feel-skill>. The audit in §3 adapts its
  native-conventions and ship-readiness lists; the architecture it recommends
  (a shared web UI inside a system web view) is not adopted here, see
  [arch-07](./arch-07_cross_platform_shared_core_standards.md) §8.
* [arch-05](./arch-05_resilient_architecture_patterns.md) §2–§3 (pure render
  logic, layout from semantic state), [arch-07](./arch-07_cross_platform_shared_core_standards.md)
  §4 and §7–§9, [proc-04](../process/proc-04_agent_workflow_standards.md) §7 (UI
  change validation), the `app` role block.
