# Swift Standards

## 1. Package Management

* **Tool:** Swift Package Manager (SPM). `Package.swift` for dependencies.
* **Version:** Swift 5.9+ (use latest stable).
* **Dependencies:** Declare in `Package.swift`. Pin versions or use ranges.

## 2. Code Style

* **Formatter:** `swiftformat` or `swift-format`. Line length 120.
* **Linter:** `swiftlint`. Configure via `.swiftlint.yml`.
* **Type Checker:** Swift compiler strict warnings. Enable all warnings as errors in release.

### Package.swift Example

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProjectName",
    platforms: [.macOS(.v13), .iOS(.v16)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0")
    ]
)
```

## 3. Naming Conventions

* **Types/Protocols:** `PascalCase`
* **Functions/Variables:** `camelCase`
* **Constants:** `camelCase` (use `let` for immutability)
* **Private:** `private` access control (no underscore prefix)
* **Files:** `PascalCase.swift` matching primary type name

## 4. Project Structure

```text
Sources/
├── Domain/
│   ├── Entities/
│   └── ValueObjects/
├── Application/
│   ├── UseCases/
│   └── Interfaces/
└── Infrastructure/
    └── Repositories/
Tests/
└── [Mirror Sources structure]
```

## 5. Language Features

* **Immutability:** Prefer `let` over `var`. Use `struct` for value types.
* **Optionals:** Use `Optional<T>` (`T?`) for nullable values. Avoid force unwrapping (`!`).
* **Protocols:** Use protocols for interfaces. Prefer protocol-oriented design.
* **Generics:** Use generics for reusable code. Use `where` clauses for constraints.

### Example

```swift
struct Email: Equatable {
    let value: String
    
    init(_ value: String) throws {
        guard value.contains("@") && value.contains(".") else {
            throw InvalidEmailError(value)
        }
        self.value = value
    }
}

enum Result<T> {
    case success(T)
    case failure(Error)
}
```

## 6. Error Handling

* **Errors:** Use `Error` protocol. Prefer `enum` for typed errors.
* **Throwing:** Use `throws` for functions that can fail. Use `try?` or `do-catch`.
* **Result Type:** Use `Result<T, Error>` for functional error handling.

```swift
enum DomainError: Error {
    case invalidEmail(String)
    case userNotFound(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidEmail(let email):
            return "Invalid email: \(email)"
        case .userNotFound(let id):
            return "User not found: \(id)"
        }
    }
}
```

## 7. Testing

* **Framework:** `XCTest`. Use `XCTAssert*` functions.
* **Mocking:** Use protocols for testability. Create test doubles manually or use `Mockingbird`.
* **Coverage:** Enable code coverage in Xcode. **95% is the absolute minimum for any module.** Target 100% for domain, 95%+ for application and infrastructure.

### Test Structure

```swift
import XCTest
@testable import Domain

final class UserTests: XCTestCase {
    func testShouldCreateUserWithValidEmail() throws {
        // Given
        let email = try Email("test@example.com")
        
        // When
        let user = User(email: email, name: "Test User")
        
        // Then
        XCTAssertEqual(user.email.value, "test@example.com")
    }
}
```

## 8. Concurrency

* **Async/Await:** Use `async`/`await` for concurrent operations (Swift 5.5+).
* **Actors:** Use `actor` for thread-safe mutable state.
* **Tasks:** Use `Task` and `TaskGroup` for structured concurrency.

```swift
actor UserRepository {
    private var users: [String: User] = [:]
    
    func findById(_ id: String) async -> User? {
        return users[id]
    }
    
    func save(_ user: User) async {
        users[user.id] = user
    }
}
```

## 9. Memory Management

* **ARC:** Automatic Reference Counting. Avoid retain cycles with `weak`/`unowned`.
* **Closures:** Use `[weak self]` or `[unowned self]` in closures to prevent cycles.
* **Value Types:** Prefer `struct` over `class` when possible.

## 10. Dependencies

### Common Libraries

* **Networking:** `URLSession` (native), `Alamofire` for complex needs
* **JSON:** `Codable` protocol (native), `SwiftyJSON` for dynamic parsing
* **Logging:** `swift-log` (server-side), `os.log` (Apple platforms)

## 11. Documentation

* **Doc Comments:** Use triple-slash (`///`) for documentation. Supports Markdown.
* **Format:** Use `- Parameter`, `- Returns`, `- Throws` tags.

```swift
/// Creates a new user with validated email address.
///
/// - Parameter email: Valid email address (must match RFC 5322)
/// - Parameter name: User's full name (non-null, non-empty)
/// - Returns: New User entity instance
/// - Throws: `InvalidEmailError` if email format is invalid
func createUser(email: String, name: String) throws -> User {
    // Implementation
}
```

## 12. Platform-Specific

* **iOS/macOS:** Follow Apple's Human Interface Guidelines.
* **Server-Side:** Use Vapor or SwiftNIO for HTTP servers.
* **Cross-Platform:** Use `#if os()` for platform-specific code.

## 13. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Use Xcode's built-in static analyzer. No major third-party SAST tool for Swift.
- **Dependency scanning:** Enable GitHub Dependabot for SPM dependencies.
- **Banned functions:** `NSExpression` with user input, `Process`/`NSTask` with unsanitized arguments.
- **Secure random:** Use `SystemRandomNumberGenerator` or `SecRandomCopyBytes` for security contexts.
