All persisted data formats must include a `version` field (integer, starting at 1).
Increment version for structural changes that alter how existing fields are read. Additive changes (new optional fields) do not require a bump.
Migration: read old format → convert in memory → write new format. Never delete source data.
Migrations compose sequentially: `v1 → v2 → v3 → vN`. Each transition is an isolated function.
Migrations must be idempotent. Use atomic writes: write to temp file, then rename.
Maintain fixture files per historical version in `tests/fixtures/` (e.g., `v1_sample.json`). Test round-trip migrations.
Test forward-incompatibility: loading a newer version must return a clear error, not crash.
Pipeline steps must be idempotent. Design for at-least-once delivery.
Validate input schema at ingestion. Reject malformed data at boundary with a clear error.
Never silently drop records. Failed records must be logged with enough context to replay.
