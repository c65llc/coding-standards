# Role: Application (UI / Frontend)

Separate data→view model transformations from view model→pixels rendering.
View model functions are pure: data in, data out, no side effects, no framework imports. Test without a display server.
Use a single source of truth for application state. State is immutable; produce new state, never mutate in place.
Side effects (API calls, storage) are isolated from state update logic.
Derive layout from semantic state (`LayoutMode` enum), not platform or user-agent detection.
Prefer `const` constructors and stateless components when possible.
Touch targets: 44×44pt minimum (iOS), 48×48dp (Android). All interactive elements need accessible labels.
Support keyboard navigation. Ensure focus order is logical. Maintain WCAG AA color contrast (4.5:1 normal text).
Avoid synchronous work on the main/UI thread. Paginate or virtualize large lists.
