---
name: naming-convention
description: Lint code against language-specific naming conventions from the standards
---

# Naming Convention Lint

Check that identifiers in the project follow the language-specific naming conventions defined in the standards.

## When to Use

- During code review, to flag inconsistent naming
- When refactoring code to match standards
- When onboarding a codebase that predates the standards
- When a user asks "does this follow our naming conventions?"

## Convention Reference

From `standards/shared/blocks/naming-conventions.md` and language-specific standards:

### Python (`lang-01`)

- Functions/variables: `snake_case`
- Classes: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Modules/files: `snake_case.py`
- Private: `_leading_underscore`

### JavaScript/TypeScript (`lang-06`, `lang-07`)

- Functions/variables: `camelCase`
- Classes/components: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Files: `kebab-case.ts` (or `PascalCase.tsx` for components)

### Java/Kotlin (`lang-02`, `lang-03`)

- Methods/variables: `camelCase`
- Classes/interfaces: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Packages: `com.example.project` (reverse domain)

### Ruby (`lang-10`)

- Methods/variables: `snake_case`
- Classes/modules: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Predicates: `method_name?`
- Dangerous methods: `method_name!`
- Files: `snake_case.rb`

### Rust (`lang-08`)

- Functions/variables: `snake_case`
- Types/traits: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Modules/files: `snake_case.rs`
- Lifetimes: `'lowercase`

### Go (`lang-12`)

- Exported: `PascalCase`
- Unexported: `camelCase`
- No `ALL_CAPS` for constants
- Acronyms: `HTTPClient`, not `HttpClient`
- Files: `snake_case.go`

### Swift (`lang-04`)

- Functions/variables: `camelCase`
- Types/protocols: `PascalCase`
- Files: `PascalCase.swift`

### Dart (`lang-05`)

- Functions/variables: `camelCase`
- Classes: `PascalCase`
- Files: `snake_case.dart`
- Constants: `camelCase` (Dart convention, not UPPER_SNAKE)

### Zig (`lang-09`, per `lang-09_zig_standards.md`)

- Functions/variables: `camelCase`
- Types: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`

### Elixir (`lang-13`)

- Functions/variables: `snake_case`
- Modules: `PascalCase`
- Predicates: `function_name?`
- Files: `snake_case.ex`

## Workflow

1. Detect the project's languages from `.standards.yml` or `detect-languages.sh`.

2. For each language, scan source files (exclude tests, vendored code, generated code):
   - **Files**: Check filenames against the expected pattern
   - **Identifiers**: Use grep patterns or language tooling to find violations

3. Common detection patterns:

   ```bash
   # Python: find camelCase function definitions (should be snake_case)
   grep -rn 'def [a-z][a-zA-Z]*[A-Z]' --include='*.py' src/

   # JavaScript: find snake_case function definitions (should be camelCase)
   grep -rn 'function [a-z_]*_[a-z]' --include='*.js' --include='*.ts' src/

   # Ruby: find camelCase method definitions (should be snake_case)
   grep -rn 'def [a-z][a-zA-Z]*[A-Z]' --include='*.rb' app/ lib/
   ```

   For more accurate results, prefer language-specific linters:
   - Python: `ruff` (naming rules via `pylint` convention checks)
   - JavaScript/TypeScript: `eslint` with `@typescript-eslint/naming-convention`
   - Ruby: `rubocop` naming cops
   - Rust: `clippy` naming lints (enabled by default)
   - Go: `golangci-lint` with `revive` naming rules

4. Report violations grouped by convention type (file naming, function naming, class naming, etc.).

## After Check

Report: "Naming conventions: N files checked, X violations found (Y file naming, Z identifier naming)."

For small numbers of violations, list each one with file, line, current name, and suggested fix.
