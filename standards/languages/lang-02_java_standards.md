# Java Standards

## 1. Build System

* **Tool:** `Maven` or `Gradle`. Prefer Gradle for modern projects.
* **Version:** Java 17+ (LTS). Use `--enable-preview` only for evaluation.
* **Dependencies:** Declare in `pom.xml` or `build.gradle`. Use dependency management BOMs.

## 2. Code Style

* **Formatter:** `google-java-format` or `palantir-java-format`. Line length 120.
* **Linter:** `checkstyle`, `spotbugs`, `error-prone`.
* **Type Checker:** Compiler strict warnings enabled. Use `@Nullable`/`@NonNull` annotations.

### Gradle Configuration

```groovy
java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

tasks.withType(JavaCompile) {
    options.compilerArgs += ['-Xlint:all', '-Werror']
}
```

## 3. Naming Conventions

* **Packages:** `com.company.project.layer` (lowercase, reverse domain)
* **Classes/Interfaces:** `PascalCase`
* **Methods/Variables:** `camelCase`
* **Constants:** `UPPER_SNAKE_CASE`
* **Private Fields:** `camelCase` (not `m_` or `_` prefix)

## 4. Project Structure

```text
src/
├── main/
│   ├── java/
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
    └── java/  # Mirror main structure
```

## 5. Class Design

* **Immutability:** Prefer immutable classes. Use `final` fields and builders.
* **Records:** Use `record` (Java 14+) for value objects and DTOs.
* **Sealed Classes:** Use `sealed` classes (Java 17+) for restricted inheritance.
* **Interfaces:** Define repository interfaces in application layer.

### Example

```java
public record Email(String value) {
    public Email {
        if (value == null || !value.matches("^[^@]+@[^@]+\\.[^@]+$")) {
            throw new IllegalArgumentException("Invalid email: " + value);
        }
    }
}

public sealed interface Result<T> permits Success, Failure {
    // Sealed interface for result types
}
```

## 6. Dependency Injection

* **Framework:** Use `Spring` or `Guice` for DI. Prefer constructor injection.
* **Configuration:** Use `@Configuration` classes or `@Bean` methods.
* **Scopes:** Use `@Singleton` for stateless services. Avoid `@RequestScope` in domain.

## 7. Testing

* **Framework:** `JUnit 5` with `AssertJ` for assertions.
* **Mocking:** `Mockito` for mocks. Use `@Mock` and `@InjectMocks`.
* **Coverage:** `JaCoCo`. **95% is the absolute minimum for any module.** Target 100% for domain, 95%+ for application and infrastructure.

### Test Structure

```java
@ExtendWith(MockitoExtension.class)
class UserServiceTest {
    @Mock
    private UserRepository userRepository;
    
    @InjectMocks
    private UserService userService;
    
    @Test
    void shouldCreateUserWithValidEmail() {
        // Given
        String email = "test@example.com";
        
        // When
        User user = userService.createUser(email, "Test User");
        
        // Then
        assertThat(user.getEmail()).isEqualTo(email);
    }
}
```

## 8. Error Handling

* **Custom Exceptions:** Checked exceptions for recoverable errors, unchecked for programming errors.
* **Domain Exceptions:** Unchecked exceptions extending `RuntimeException`.
* **Context:** Include cause in exception constructor. Use `getMessage()` for user-facing messages.

```java
public class DomainException extends RuntimeException {
    public DomainException(String message) {
        super(message);
    }
    
    public DomainException(String message, Throwable cause) {
        super(message, cause);
    }
}
```

## 9. Collections & Streams

* **Immutable Collections:** Use `List.of()`, `Set.of()`, `Map.of()` for immutable collections.
* **Streams:** Prefer streams for transformations. Keep operations readable.
* **Optional:** Use `Optional<T>` for nullable return values. Avoid `Optional` in fields or parameters.

## 10. Annotations

* **Null Safety:** Use `@Nullable` and `@NonNull` (JSR-305 or JetBrains).
* **Validation:** Use `javax.validation` (`@NotNull`, `@Email`, `@Size`).
* **Documentation:** Use JavaDoc for public APIs. Include `@param`, `@return`, `@throws`.

## 11. Dependencies

### Common Libraries

* **HTTP:** `OkHttp`, `Retrofit` (REST clients)
* **Database:** `JPA`/`Hibernate` (ORM), `JOOQ` (type-safe SQL)
* **JSON:** `Jackson` or `Gson`
* **Logging:** `SLF4J` with `Logback`

## 12. Documentation

* **JavaDoc:** Required for all public classes, methods, and fields.
* **Format:** Use standard JavaDoc tags. Include examples for complex methods.

```java
/**
 * Creates a new user with validated email address.
 *
 * @param email valid email address (must match RFC 5322)
 * @param name  user's full name (non-null, non-empty)
 * @return new User entity instance
 * @throws InvalidEmailException if email format is invalid
 * @throws IllegalArgumentException if name is null or empty
 */
public User createUser(String email, String name) {
    // Implementation
}
```

## 13. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Use SpotBugs with Find Security Bugs plugin in CI.
- **Dependency scanning:** Run OWASP Dependency-Check (`gradle dependencyCheckAnalyze`).
- **Banned functions:** `Runtime.exec()` with unsanitized string, `ObjectInputStream.readObject()` on untrusted data, `ScriptEngine.eval()`.
- **Secure random:** Use `java.security.SecureRandom`, not `java.util.Random`, for security contexts.
