# Swift

Use Swift Package Manager (SPM). `Package.swift` for all dependencies. Swift 5.9+.
Format with `swiftformat` or `swift-format`. Lint with `swiftlint`. Treat warnings as errors in release builds.
Prefer `let` over `var`. Use `struct` for value types. Use `class` only when reference semantics needed.
Use protocols for interfaces. Prefer protocol-oriented design.
Use `Optional<T>` (`T?`) for nullable values. Avoid force unwrapping (`!`).
Use `enum` with associated values for typed errors. Use `Result<T, Error>` for functional error handling.
Use `[weak self]` in closures to prevent retain cycles.
Naming: `camelCase` functions/variables/constants, `PascalCase` types/protocols, `private` access control (no underscore prefix).
Test with `XCTest`. Use protocols for testability. 95% coverage minimum, 100% for domain.
Use `async`/`await` (Swift 5.5+). Use `actor` for thread-safe mutable state.
Security: Xcode static analyzer; GitHub Dependabot for SPM. Banned: `NSExpression` with user input, `Process` with unsanitized args. Use `SecRandomCopyBytes` for security contexts.
