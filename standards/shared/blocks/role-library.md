Design the public API surface first. Keep it minimal and stable.
Everything not explicitly `pub`/`export`ed is internal. Internal APIs may change without semver bump.
Follow semantic versioning strictly: MAJOR breaking changes, MINOR backward-compatible additions, PATCH bug fixes.
Minimize external dependencies. Never depend on application-layer frameworks (web servers, ORMs).
Avoid singleton state and global mutable state.
Document every public API item: parameters, return values, errors, and usage examples.
Publish a CHANGELOG.md. Every release must have an entry.
Write tests that exercise the public API as a consumer would, not internal implementation details.
