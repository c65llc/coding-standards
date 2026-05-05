# Swift Standards

## 1. Package Management

* **Tool:** Swift Package Manager (SPM). `Package.swift` for dependencies.
* **Version:** Swift 5.9+ (use latest stable).
* **Dependencies:** Declare in `Package.swift`. Pin versions or use ranges.
* **Age Gate:** Do not adopt any Swift package version (tag/release) published less than 3 days ago. Verify the GitHub release date before upgrading. See `sec-01` §5 for exceptions.

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
- **Banned functions:** See [sec-01_security_standards.md](../security/sec-01_security_standards.md) for the complete banned-functions list with language-specific examples.
- **Secure random:** Use `SystemRandomNumberGenerator` or `SecRandomCopyBytes` for security contexts.

## 14. Build & Project Generation (Apple platforms)

For app targets (iOS/macOS/tvOS/watchOS/visionOS), the `.xcodeproj` is a build artifact, not a source file. Treat a declarative project spec as the source of truth, and set code-signing build settings deliberately so device builds work the first time.

### 14.1 Project file generation

* **Tool:** Use [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) or Tuist for any project with more than one target. Hand-maintained `.xcodeproj` files cause merge conflicts and silent setting drift.
* **Source of truth:** `project.yml` (or `Project.swift`) is checked in; the generated `.xcodeproj` is **gitignored**. Never edit build settings in the Xcode UI — regeneration overwrites them.
* **Regenerate before build:** CI and local `make build` targets must run `xcodegen generate` (or `tuist generate`) before invoking `xcodebuild`, so the project file always matches the spec.

### 14.2 Code signing — the rules

These settings are easy to get wrong, and the failure modes are confusing (UI looks correct, device install still fails). Follow these rules:

1. **Set `DEVELOPMENT_TEAM` to the 10-character Apple Developer Team ID.** Team IDs are public identifiers (visible in App Store listings); safe to commit. Empty `DEVELOPMENT_TEAM` makes device builds unsigned.
2. **Use `CODE_SIGN_STYLE: Automatic`** for app targets unless you have a specific reason to manage profiles manually (e.g., enterprise distribution). Automatic signing handles simulator and device correctly with a valid team.
3. **Never set `CODE_SIGNING_ALLOWED: NO` or `CODE_SIGNING_REQUIRED: NO` at the `base` settings level.** Base settings apply to **every** configuration and **every** destination — including device builds, where they produce an unsigned binary that iOS rejects with a "code is unsigned" error at install time. The Xcode UI will still show "Automatic" signing while the build silently skips it.
4. **If a CI lane genuinely needs unsigned simulator builds** (e.g., a hosted runner without keychain access), scope the override to that configuration only — never the base — and document why:

   ```yaml
   # project.yml — XcodeGen example
   configs:
     Debug: debug
     Release: release
     DebugCI: debug      # CI-only config, simulator builds without keychain
   settings:
     base:
       DEVELOPMENT_TEAM: ABCDE12345
       CODE_SIGN_STYLE: Automatic
     configs:
       DebugCI:
         CODE_SIGNING_ALLOWED: NO
         CODE_SIGNING_REQUIRED: NO
   ```

   Prefer the simpler path: provision the CI runner with a signing identity (e.g., via `apple-actions/import-codesign-certs`) and keep one signing posture across all configurations.

### 14.3 Minimal correct app-target spec

```yaml
# project.yml
settings:
  base:
    SWIFT_VERSION: "5.9"
    DEVELOPMENT_TEAM: ABCDE12345        # 10-char Apple Developer Team ID
    CODE_SIGN_STYLE: Automatic
    ENABLE_USER_SCRIPT_SANDBOXING: YES
targets:
  MyApp:
    type: application
    platform: iOS
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.myapp
```

### 14.4 Diagnostic checklist for "code is unsigned" / device-install failures

When a build looks correctly configured in Xcode but the device rejects it:

1. **Inspect the generated `.xcodeproj`, not the UI.** `grep -E "DEVELOPMENT_TEAM|CODE_SIGN" *.xcodeproj/project.pbxproj | sort -u` — verify `DEVELOPMENT_TEAM` is set and no `CODE_SIGNING_ALLOWED = NO` lines appear.
2. **Confirm `xcodegen generate` ran since the last spec change.** UI edits without a corresponding `project.yml` change get overwritten on regen.
3. **Check `base` vs. per-config settings.** A `NO` at base overrides any device-specific config.
4. **Run `codesign -dvv <path-to-built-.app>` on the build product.** "code object is not signed at all" confirms the binary is unsigned regardless of UI state.

### 14.5 Re-enabling signing surfaces latent target-config gaps

Disabling signing at `base` doesn't only break device installs — it also masks per-target configuration that the build system would otherwise reject. Common gap: a unit-test or extension target with no `Info.plist` and no `GENERATE_INFOPLIST_FILE: YES`. The signing pass needs a plist to embed the signature; with signing turned off it never runs the check, and the build silently succeeds. The moment signing is re-enabled, xcodebuild fails with:

> Cannot code sign because the target does not have an Info.plist file and one is not being generated automatically.

**Implication:** when re-enabling signing on an existing project, run `xcodebuild test` (not just `xcodebuild build`) against every scheme — every target that participates in the build must independently satisfy signing prerequisites. For test bundles and other auxiliary targets that don't need a hand-authored plist, set `GENERATE_INFOPLIST_FILE: YES` on the target's settings:

```yaml
targets:
  MyAppTests:
    type: bundle.unit-test
    platform: iOS
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES   # required once signing is enabled
        BUNDLE_LOADER: $(TEST_HOST)
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/MyApp.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/MyApp
```
