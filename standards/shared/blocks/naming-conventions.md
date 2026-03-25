Use verbose, descriptive names. Avoid abbreviations. Functions are verbs. Classes are nouns.
Boolean variables: `is_`, `has_`, `should_`, `can_` prefixes.
Comments explain "why", never "what".

Python: `snake_case` variables/functions/modules, `PascalCase` classes, `UPPER_SNAKE_CASE` constants, `_leading_underscore` private.
JavaScript/TypeScript: `camelCase` variables/functions, `PascalCase` classes/components/types, `kebab-case` files/dirs, `UPPER_SNAKE_CASE` constants.
Java/Kotlin: `camelCase` methods/variables, `PascalCase` classes, `UPPER_SNAKE_CASE` constants, reverse-domain lowercase packages.
Ruby: `snake_case` methods/variables/files, `PascalCase` classes/modules, `?` suffix predicates, `!` suffix dangerous methods.
Rust/Zig: `snake_case` functions/variables, `PascalCase` types/structs/enums, `UPPER_SNAKE_CASE` constants.
Go: `camelCase` unexported identifiers, `PascalCase` exported functions/types/constants; `ALL_CAPS` not used (Go uses `PascalCase` for exported constants); short lowercase package names without underscores.
Elixir: `snake_case` functions/variables/atoms/files, `PascalCase` modules/aliases; `UPPER_SNAKE_CASE` not used (use module attributes `@name` instead); `?` suffix for predicates, `!` suffix for raising variants.
