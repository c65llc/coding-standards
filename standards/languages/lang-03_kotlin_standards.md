# Kotlin Standards

## 1. Build System

* **Tool:** `Gradle` with Kotlin DSL. Use Kotlin 1.9+.
* **Version:** Target JVM 17+ or Kotlin/Native, Kotlin/JS as appropriate.
* **Dependencies:** Declare in `build.gradle.kts`. Use version catalogs.

## 2. Code Style

* **Formatter:** `ktlint` or IntelliJ formatter. Line length 120.
* **Linter:** `detekt` for static analysis.
* **Type Checker:** Compiler strict mode. Use null safety features.

### Gradle Configuration

```kotlin
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
    kotlinOptions {
        jvmTarget = "17"
        freeCompilerArgs = listOf("-Xjsr305=strict")
    }
}
```

## 3. Naming Conventions

* **Packages:** `com.company.project.layer` (lowercase)
* **Classes/Objects:** `PascalCase`
* **Functions/Variables:** `camelCase`
* **Constants:** `UPPER_SNAKE_CASE` or `const val` in companion objects
* **Private Properties:** `camelCase` (no underscore prefix)

## 4. Project Structure

```text
src/
├── main/
│   ├── kotlin/
│   │   └── com/company/project/
│   │       ├── domain/
│   │       │   ├── entities/
│   │       │   └── valueobjects/
│   │       ├── application/
│   │       │   ├── usecases/
│   │       │   └── interfaces/
│   │       └── infrastructure/
│   │           └── persistence/
│   └── resources/
└── test/
    └── kotlin/  # Mirror main structure
```

## 5. Language Features

* **Immutability:** Prefer `val` over `var`. Use `data class` for value objects.
* **Null Safety:** Leverage nullable types (`String?`). Use `?.`, `?:`, `!!` judiciously.
* **Sealed Classes:** Use `sealed class` or `sealed interface` for restricted hierarchies.
* **Extension Functions:** Use for utility functions. Keep in appropriate packages.

### Example

```kotlin
data class Email(val value: String) {
    init {
        require(value.matches(Regex("^[^@]+@[^@]+\\.[^@]+$"))) {
            "Invalid email: $value"
        }
    }
}

sealed interface Result<out T> {
    data class Success<T>(val data: T) : Result<T>
    data class Failure(val error: Throwable) : Result<Nothing>
}
```

## 6. Dependency Injection

* **Framework:** Use `Koin` or `Kodein` for Kotlin-native DI. Spring also supported.
* **Style:** Prefer constructor injection. Use property injection sparingly.

## 7. Testing

* **Framework:** `JUnit 5` with `kotest` or `spek` for BDD-style tests.
* **Assertions:** Use `kotest` matchers or `assertk`.
* **Mocking:** `MockK` for mocking. Use `mockk()` and `every {}`.

### Test Structure

```kotlin
class UserServiceTest {
    private val userRepository = mockk<UserRepository>()
    private val userService = UserService(userRepository)
    
    @Test
    fun `should create user with valid email`() {
        // Given
        val email = "test@example.com"
        
        // When
        val user = userService.createUser(email, "Test User")
        
        // Then
        user.email shouldBe email
    }
}
```

## 8. Error Handling

* **Exceptions:** Use typed exceptions. Prefer `Result<T>` for functional error handling.
* **Domain Exceptions:** Unchecked exceptions extending `RuntimeException` or custom sealed classes.
* **Context:** Include cause and context in exceptions.

```kotlin
sealed class DomainException(message: String, cause: Throwable? = null) :
    RuntimeException(message, cause) {
    
    class InvalidEmailException(email: String) :
        DomainException("Invalid email: $email")
}
```

## 9. Collections & Sequences

* **Immutable Collections:** Prefer `listOf()`, `setOf()`, `mapOf()`.
* **Mutable Collections:** Use `mutableListOf()` only when mutation is required.
* **Sequences:** Use `sequence {}` for lazy transformations of large collections.

## 10. Coroutines

* **Use When:** Async operations, I/O-bound tasks.
* **Scope:** Use `CoroutineScope` and structured concurrency.
* **Suspending Functions:** Mark async functions with `suspend`. Use `Flow` for streams.

```kotlin
suspend fun fetchUser(id: String): User = withContext(Dispatchers.IO) {
    userRepository.findById(id) ?: throw UserNotFoundException(id)
}
```

## 11. Dependencies

### Common Libraries

* **HTTP:** `ktor-client` or `OkHttp` with `Retrofit`
* **Database:** `Exposed` (SQL), `Room` (Android)
* **JSON:** `kotlinx.serialization` or `Gson`
* **Logging:** `kotlin-logging` wrapper for SLF4J

## 12. Documentation

* **KDoc:** Use KDoc format (similar to JavaDoc). Required for public APIs.
* **Format:** Use `@param`, `@return`, `@throws` tags.

```kotlin
/**
 * Creates a new user with validated email address.
 *
 * @param email valid email address (must match RFC 5322)
 * @param name user's full name (non-null, non-empty)
 * @return new User entity instance
 * @throws InvalidEmailException if email format is invalid
 */
fun createUser(email: String, name: String): User {
    // Implementation
}
```

## 13. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Use SpotBugs with Find Security Bugs plugin or detekt security ruleset in CI.
- **Dependency scanning:** Run OWASP Dependency-Check (`gradle dependencyCheckAnalyze`).
- **Banned functions:** `Runtime.exec()` with unsanitized string, `ObjectInputStream.readObject()` on untrusted data, `ScriptEngine.eval()`.
- **Secure random:** Use `java.security.SecureRandom`, not `java.util.Random`, for security contexts.
