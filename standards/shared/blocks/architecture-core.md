Dependencies point inward only: Domain ← Application ← Infrastructure ← Apps.

- **Domain:** Pure business logic. No external dependencies. Entities, value objects.
- **Application:** Orchestrates domain. Defines use cases and repository interfaces.
- **Infrastructure:** Implements interfaces. Handles DB, APIs, file systems.
- **Apps:** Entry points (CLI, web, workers). Depends on all inner layers.

SOLID principles mandatory. Violations require justification in code comments.
Validate inputs at boundaries. Fail fast; reject invalid state immediately.
Define typed custom errors in Domain. No generic exceptions.
Use structured logging with request ID, user ID, and operation context.
Secondary/derived subsystems (mirrors, indexes, sync, telemetry) are best-effort and error-isolated — a failure there must never break the primary write path.
When you catch-and-degrade, preserve and surface the original cause; never swallow it behind a generic "failed" message.
