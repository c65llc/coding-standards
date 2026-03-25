# Java

Use Gradle (preferred) or Maven. Java 17+ (LTS). Use Gradle version catalogs.
Format with `google-java-format` or `palantir-java-format` (line length 120). Run `checkstyle`, `spotbugs`, `error-prone` in CI.
Use `record` (Java 14+) for value objects and DTOs. Use `sealed` classes/interfaces (Java 17+) for restricted hierarchies.
Use `Optional<T>` for nullable returns. Avoid `Optional` in fields or parameters. Prefer `List.of()`, `Set.of()` for immutable collections.
Naming: `camelCase` methods/variables, `PascalCase` classes/interfaces, `UPPER_SNAKE_CASE` constants, reverse-domain lowercase packages.
Test with `JUnit 5` + `AssertJ`. Mock with `Mockito`. Measure with `JaCoCo`. 95% minimum, 100% for domain.
Prefer constructor injection for DI. Checked exceptions for recoverable errors; unchecked for programming errors.
Security: SpotBugs + Find Security Bugs and OWASP Dependency-Check in CI. Banned: `Runtime.exec()` with unsanitized input, `ObjectInputStream.readObject()` on untrusted data, `ScriptEngine.eval()`. Use `java.security.SecureRandom`.
