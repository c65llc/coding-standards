# Ruby on Rails

All base Ruby standards apply. Rails 7.2+. Add `rubocop-rails` gem to `.rubocop.yml`.

Model structure order (enforced by `Layout/ClassStructure`): inclusions → gem config → constants → attributes → enums → serializers → associations → nested attributes → scopes → validations → callbacks → public class methods → initializer → public methods → protected → private.

Validations: use `validates` (declarative) over `validate` (custom method) when possible.
Scopes: name as adjectives or noun phrases (`active`, `recently_active`). No `get_`/`find_` prefixes.
Callbacks: minimize. Use service objects for complex side effects. Never use callbacks for cross-model business logic.
Enums: always hash syntax with explicit integers: `enum :status, { draft: 0, published: 1 }`.
Controllers: thin — delegate to service objects. Actions ≤10 lines. Strong params via private method. Never `params.permit!`.
Service objects: in `app/application/use_cases/` or `app/services/`. Single `.call` class method. Return result with `success?`.
Background jobs (Sidekiq): pass primitive IDs, never ActiveRecord objects. Jobs must be idempotent.
Database: always add foreign keys and indexes. Use DB-level constraints (NOT NULL, UNIQUE) alongside model validations.
Security: CSRF always enabled. Never interpolate user input into SQL. Run `brakeman` in CI.
