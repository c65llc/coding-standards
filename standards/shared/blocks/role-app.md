Separate data→view model transformations from view model→pixels rendering.
View model functions are pure: data in, data out, no side effects, no framework imports. Test without a display server.
Use a single source of truth for application state. State is immutable; produce new state, never mutate in place.
Side effects (API calls, storage) are isolated from state update logic.
Derive layout from semantic state (`LayoutMode` enum), not platform or user-agent detection.
Prefer stateless components when possible; keep view construction cheap and side-effect free (the language block names the framework's compile-time-constant idiom, if any).
Touch targets: 44×44pt minimum (iOS), 48×48dp (Android). All interactive elements need accessible labels.
Support keyboard navigation. Ensure focus order is logical. Maintain WCAG AA color contrast (4.5:1 normal text).
Avoid synchronous work on the main/UI thread. Paginate or virtualize large lists.
UI changes MUST be validated against reference designs in `assets/designs/<route-or-component>/<state>.png` — render, screenshot, diff. Human-gated approval; pixel-diff alone is too noisy to gate on. Full protocol in `proc-04 § 7 UI Change Validation`.
