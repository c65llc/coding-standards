# Dart Standards

## 1. Package Management

* **Tool:** `pub` (Dart's package manager). `pubspec.yaml` for dependencies.
* **Version:** Dart 3.0+ (null safety required).
* **Dependencies:** Declare in `pubspec.yaml`. Pin versions for production.

## 2. Code Style

* **Formatter:** `dart format`. Run via `make fmt`.
* **Linter:** `dart analyze` with `analysis_options.yaml`. Use `linter` package rules.
* **Type Checker:** Strong mode enabled by default. No implicit `dynamic`.

### analysis_options.yaml

```yaml
include: package:linter/analyzer.yaml

linter:
  rules:
    - always_declare_return_types
    - avoid_empty_else
    - prefer_const_constructors
    - prefer_final_fields

analyzer:
  errors:
    missing_return: error
  exclude:
    - build/**
```

## 3. Naming Conventions

* **Files:** `snake_case.dart`
* **Classes/Enums:** `PascalCase`
* **Variables/Functions:** `camelCase`
* **Constants:** `lowerCamelCase` (use `const` or `static const`)
* **Private:** `_leadingUnderscore` for library-private

## 4. Project Structure

```text
lib/
├── domain/
│   ├── entities/
│   └── value_objects/
├── application/
│   ├── use_cases/
│   └── interfaces/
└── infrastructure/
    └── repositories/

test/
└── [Mirror lib structure]
```

## 5. Language Features

* **Null Safety:** Use nullable types (`String?`). Use `!` for null assertion sparingly.
* **Immutability:** Prefer `final` over `var`. Use `const` constructors when possible.
* **Records:** Use `record` (Dart 3.0+) for value objects and data transfer.
* **Patterns:** Use pattern matching (Dart 3.0+) for destructuring and matching.

### Example

```dart
class Email {
  final String value;
  
  Email(this.value) {
    if (!value.contains('@') || !value.contains('.')) {
      throw InvalidEmailException(value);
    }
  }
}

sealed class Result<T> {
  const Result();
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends Result<T> {
  final Exception error;
  const Failure(this.error);
}
```

## 6. Dependency Injection

* **Framework:** Use `get_it` or `injectable` for DI. Prefer constructor injection.
* **Code Generation:** Use `build_runner` for generated code (annotations).

## 7. Testing

* **Framework:** `test` package. Use `expect()` for assertions.
* **Mocking:** `mockito` with code generation. Use `@GenerateMocks` annotation.
* **Coverage:** `test_coverage`. **95% is the absolute minimum for any module.** Target 100% for domain, 95%+ for application and infrastructure.

### Test Structure

```dart
import 'package:test/test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([UserRepository])
void main() {
  group('UserService', () {
    test('should create user with valid email', () {
      // Given
      final email = Email('test@example.com');
      
      // When
      final user = UserService.createUser(email, 'Test User');
      
      // Then
      expect(user.email.value, equals('test@example.com'));
    });
  });
}
```

## 8. Error Handling

* **Exceptions:** Use typed exceptions extending `Exception` or `Error`.
* **Result Pattern:** Use `Result<T>` sealed class for functional error handling.
* **Async Errors:** Use `Future<T>` with error handling or `Result<Future<T>>`.

```dart
class DomainException implements Exception {
  final String message;
  DomainException(this.message);
  
  @override
  String toString() => 'DomainException: $message';
}

class InvalidEmailException extends DomainException {
  InvalidEmailException(String email) : super('Invalid email: $email');
}
```

## 9. Async/Await

* **Futures:** Use `Future<T>` for async operations. Prefer `async`/`await` over `.then()`.
* **Streams:** Use `Stream<T>` for reactive data. Use `StreamController` for custom streams.
* **Isolates:** Use `Isolate.spawn()` for CPU-intensive tasks.

```dart
Future<User> fetchUser(String id) async {
  try {
    final user = await userRepository.findById(id);
    return user ?? throw UserNotFoundException(id);
  } catch (e) {
    throw UserFetchException('Failed to fetch user: $id', e);
  }
}
```

## 10. Dependencies

### Common Libraries

* **HTTP:** `http` package or `dio` for advanced features
* **JSON:** `json_serializable` with code generation
* **State Management:** `riverpod` or `bloc` (Flutter), `get_it` (server)
* **Logging:** `logger` package

## 11. Documentation

* **Doc Comments:** Use triple-slash (`///`) for documentation. Supports Markdown.
* **Format:** Use `[param]`, `[returns]`, `[throws]` tags.

```dart
/// Creates a new user with validated email address.
///
/// [email] Valid email address (must match RFC 5322)
/// [name] User's full name (non-null, non-empty)
///
/// Returns new User entity instance.
///
/// Throws [InvalidEmailException] if email format is invalid.
User createUser(Email email, String name) {
  // Implementation
}
```

## 12. Flutter-Specific

* **Widgets:** Use `const` constructors when possible. Prefer `StatelessWidget` over `StatefulWidget`.
* **State Management:** Use `riverpod` or `bloc` for complex state. Avoid `setState` for business logic.
* **Testing:** Use `flutter_test` for widget tests. Use `golden` tests for UI regression.

## 13. Server-Side

* **Framework:** Use `shelf` or `dart_frog` for HTTP servers.
* **Isolates:** Leverage isolates for concurrent request handling.
* **Database:** Use `postgres` or `mongo_dart` packages.

## 14. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Run `dart analyze` with security-relevant lint rules enabled.
- **Dependency scanning:** Enable GitHub Dependabot for pub dependencies.
- **Secure random:** Use `dart:math Random.secure()` for security contexts, not `Random()`.
