# Data Versioning & Migration Standards

## 1. Version Field Requirement

All persisted data formats MUST include a version number.

* **Field name:** `version` (integer, starting at 1).
* **Location:** Top-level field in the serialized format (JSON root, file header, database schema metadata).
* **Increment policy:** Bump the version for any structural change that alters how existing fields are read or interpreted. Additive changes (new optional fields with defaults) do not require a version bump.

### Example

```json
{
  "version": 2,
  "name": "My Project",
  "documents": [],
  "child_order": {}
}
```

## 2. Migration Strategy

Use **side-by-side migration**: read the old format, convert to the new format in memory, write the new format. Never delete old data during migration.

### Load Flow

```text
1. Read version field from persisted data
2. If version < CURRENT_VERSION → run migration chain (v1→v2→...→vN)
3. If version == CURRENT_VERSION → deserialize directly
4. If version > CURRENT_VERSION → error: "This data was created by a newer version of the application"
```

### Migration Chain

Each version transition is an isolated function:

```text
migrate_v1_to_v2(data_v1) → data_v2
migrate_v2_to_v3(data_v2) → data_v3
```

Migrations compose sequentially. A v1 document loaded by a v3 app runs: `v1 → v2 → v3`.

### Safety Rules

* **Never delete source data.** After migration, original files remain on disk. Only write new format alongside or in a new location.
* **Idempotent migrations.** Running a migration on already-migrated data must be a no-op or produce the same result.
* **Atomic writes.** Write to a temporary file, then rename. Avoid partial writes on crash.

## 3. Schema Evolution Patterns

### Additive Changes (No Version Bump)

* New optional fields with sensible defaults.
* New enum variants that existing code can ignore.

### Structural Changes (Version Bump Required)

* Renaming or removing fields.
* Changing field types (e.g., `string` → `object`).
* Restructuring nested objects (e.g., merging `folder_order` + `document_order` into `child_order`).
* Changing the semantics of an existing field.

## 4. Testing Migrations

* **Fixture files:** Maintain sample data files for each historical version in `tests/fixtures/` (e.g., `v1_sample.json`, `v2_sample.json`).
* **Round-trip tests:** Load a vN fixture → migrate to current → verify all data is preserved.
* **Forward-incompatibility test:** Load a fixture with `version: CURRENT + 1` → verify the app returns a clear error, not a crash.
* **Edge cases:** Empty documents, maximum-size documents, documents with all optional fields missing.

## 5. Documentation

* Document each version's schema in a `SCHEMA.md` or equivalent file.
* When bumping versions, add a changelog entry describing what changed and why.
* ADRs are appropriate for major schema redesigns (e.g., changing the persistence model).
