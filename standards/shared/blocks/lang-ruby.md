# Ruby

Use `bundler`. Commit `Gemfile.lock`. Pin exact versions for production. Ruby 3.2+. Use `mise` for version management.
Lint and format with `rubocop`. Use `.rubocop.yml` with `NewCops: enable`. Run `rubocop -a` for safe auto-corrections.
Add `# frozen_string_literal: true` to every file.
Use Sorbet for static typing: every file needs `# typed: strict`, every method needs a `sig`. Use `tapioca` for RBI generation.
No `T.untyped` without justification. Use `T.nilable(Type)` for nullable values.
Naming: `snake_case` methods/variables/files, `PascalCase` classes/modules, `UPPER_SNAKE_CASE` constants, `?` suffix predicates, `!` suffix dangerous methods.
Test with `rspec`. Use `factory_bot` for test data (no fixtures). Use `simplecov`. 95% minimum, 100% for domain.
Define custom exceptions in domain layer inheriting from a domain base exception. Never use bare `rescue`.
Security: `rubocop-security` rules and `bundle-audit check --update` in CI. Banned: `eval()`, `send()` with user input, `Marshal.load()` (untrusted), `YAML.load()`. Use `SecureRandom.hex()`, not `rand()`.
