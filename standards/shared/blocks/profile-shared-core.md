Logic is shared and written once in the core; rendering is written per platform in that platform's toolkit. A behavior difference between platforms is a bug, never a platform characteristic.
The core has no I/O and no ambient state: clock, id minting, locale and timezone are injected by the shell.
The core exposes a coarse-grained, serializable facade (records, enums, strings). Shells never reach past it or hold a live handle into core internals.
Conformance is golden vectors: one language-neutral fixture set replayed through every binding, through the FFI, not beside it.
Generated bindings and artifacts (wasm packages, FFI bindings, emitted tokens) are committed and drift-gated from a cold build in CI.
A UI change applies to every platform by default. Narrowing to one platform is written into the issue or PR with the reason; silence means all platforms.
Prefer a native shell over a web view when platform feel is a product goal. A web view is an interim step recorded in an ADR, never a silent destination.
Before recommending a product shape, run the decision tree in `arch-07` §8 and be willing to conclude this profile does not apply.
Before calling a shell done, walk the native-shell audit in `arch-07` §9 on the running app.
Every recommendation, review finding and ADR under this profile names what it gives up (`arch-07` T10).
Full standard: `arch-07_cross_platform_shared_core_standards.md` (tenets §7, decision tree §8, audit §9).
