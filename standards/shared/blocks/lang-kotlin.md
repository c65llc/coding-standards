# Kotlin

Use Gradle with Kotlin DSL (`build.gradle.kts`). Kotlin 1.9+, JVM 17+. Use version catalogs.
Format with `ktlint`. Run `detekt` for static analysis. Enable null-safety strict mode in compiler.
Prefer `val` over `var`. Use `data class` for value objects and DTOs.
Use `sealed class`/`sealed interface` for restricted hierarchies. Use `listOf()`, `setOf()` for immutable collections.
Leverage nullable types (`String?`) with `?.`, `?:`. Avoid `!!` unless safety is proven.
Naming: `camelCase` functions/variables, `PascalCase` classes/objects, `UPPER_SNAKE_CASE` constants, reverse-domain lowercase packages.
Test with `JUnit 5` + `kotest`. Mock with `MockK`. 95% coverage minimum, 100% for domain.
Use coroutines for async. Mark suspending functions with `suspend`. Use `Flow` for streams. Use structured concurrency via `CoroutineScope`.
Security: detekt security ruleset and OWASP Dependency-Check in CI. Banned: `Runtime.exec()` with unsanitized input, `ObjectInputStream.readObject()` on untrusted data. Use `java.security.SecureRandom`.
