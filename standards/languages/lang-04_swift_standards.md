# Swift Standards

## 1. Package Management

* **Tool:** Swift Package Manager (SwiftPM). `Package.swift` for dependencies.
* **Version:** Swift 6.0+ (`// swift-tools-version: 6.0`). Use the latest stable toolchain; the Swift 6 language mode with strict concurrency is the baseline (see §8).
* **Dependencies:** Declare in `Package.swift`. Pin versions or use ranges.
* **Lockfile:** Commit `Package.resolved` for apps, executables, and anything with a CI build. Libraries consumed by other packages may omit it. Enforced by `lint-checks/swift/package-resolved`.
* **Age Gate:** Do not adopt any Swift package version (tag/release) published less than 3 days ago. Verify the GitHub release date before upgrading. See `sec-01` §5 for exceptions.

## 2. Code Style

* **Formatter + Linter (default gate):** `swift-format`. It ships with the Swift 6 toolchain (`swift format`), so every contributor and CI runner has it without a Homebrew install. Configure via `.swift-format` (JSON); line length 120. CI runs `swift format lint --strict --recursive Sources Tests` and fails on any diagnostic. Enforced by `lint-checks/swift/swift-format-config`.
* **SwiftLint (optional):** Add `swiftlint` only for rules swift-format does not cover (e.g. `force_unwrapping`, `todo`). It is not bundled with Xcode, so it must never be the only formatting gate — a project with `.swiftlint.yml` but no `.swift-format` is non-compliant.
* **Warnings as errors:** Build with warnings as errors in CI, not just in release. For SwiftPM: `swift build -Xswiftc -warnings-as-errors` and `swift test -Xswiftc -warnings-as-errors`, or `.treatAllWarnings(as: .error)` in `swiftSettings` on tools 6.2+. For Xcode targets: `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` in `project.yml`. Enforced by `lint-checks/swift/warnings-as-errors`.

### Package.swift Example

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProjectName",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0")
    ],
    targets: [
        .target(
            name: "Domain",
            swiftSettings: [
                // Swift 6 language mode == strict concurrency. Do not downgrade
                // with -strict-concurrency=minimal; fix the diagnostics instead.
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
```

### .swift-format Example

```json
{
  "version": 1,
  "lineLength": 120,
  "indentation": { "spaces": 4 },
  "respectsExistingLineBreaks": true,
  "rules": {
    "NeverForceUnwrap": true,
    "NeverUseImplicitlyUnwrappedOptionals": true
  }
}
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

* **Framework:** `XCTest` (`XCTAssert*`) or Swift Testing (`import Testing`, `@Test`, `#expect`). Pick one per package; both run under `swift test`.
* **Mocking:** Use protocols for testability. Create test doubles manually or use `Mockingbird`.
* **Coverage:** `swift test --enable-code-coverage` (or Xcode coverage). **95% is the absolute minimum for any module.** Target 100% for domain, 95%+ for application and infrastructure.
* **Hardware-dependent tests skip explicitly.** A GPU/Metal test on a host without a Metal device (Linux CI, some virtualized macOS runners) must skip with a reason — never silently pass, and never guard the assertions with `if let device`. Skipped tests show up in the report; a hollow pass does not.

```swift
import XCTest
#if canImport(Metal)
import Metal
#endif

final class RendererTests: XCTestCase {
    override func setUpWithError() throws {
        #if canImport(Metal)
        // Skip, don't pass: the report shows "skipped (No Metal device…)".
        try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "No Metal device on this host")
        #else
        // Linux CI: Metal is not even importable. Still a recorded skip, never a build failure.
        throw XCTSkip("Metal is unavailable on this platform")
        #endif
    }

    #if canImport(Metal)
    func testShouldRenderTriangle() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = Renderer(device: device)
        XCTAssertEqual(try renderer.render(.triangle).vertexCount, 3)
    }
    #endif
}

// Swift Testing equivalent
#if canImport(Metal)
@Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "No Metal device on this host"))
func rendersTriangle() { /* ... */ }
#else
@Test(.disabled("Metal is unavailable on this platform"))
func rendersTriangle() {}
#endif
```

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

## 8. Concurrency (Swift 6 strict concurrency baseline)

* **Language mode:** Every target compiles in Swift 6 language mode (`.swiftLanguageMode(.v6)`), which makes data-race safety a compile error. Do not opt a target down to `-strict-concurrency=minimal` or `targeted` to silence diagnostics; fix the isolation instead. `@preconcurrency import` is acceptable only for third-party modules that have not adopted `Sendable`, with a comment naming the upstream issue.
* **Async/Await:** Use `async`/`await` for concurrent operations.
* **Actors:** Use `actor` for thread-safe mutable state. UI state is `@MainActor`. Mark reference types that cross isolation boundaries `final` and `Sendable`, or keep them inside an actor.
* **Tasks:** Use `Task`, `TaskGroup`, and `async let` for structured concurrency. Unstructured `Task { }` needs an owner that cancels it.
* **Sendable closures:** Closures handed to another isolation domain must be `@Sendable`; capture only `Sendable` values.

```swift
actor UserRepository {
    private var users: [String: User] = [:]

    func findById(_ id: String) -> User? {
        users[id]
    }

    func save(_ user: User) {
        users[user.id] = user
    }
}
```

### 8.1 Actor-owned opaque handles (C, Metal, GPU, file descriptors)

Opaque handles from C libraries are not `Sendable`, and an actor's `deinit` is `nonisolated` — it cannot touch actor-isolated state to release the handle. The pattern that satisfies both strict concurrency and deterministic cleanup:

1. **Own the handle inside a `final class` guarded by `OSAllocatedUnfairLock`** (Apple platforms, iOS 16+/macOS 13+) or a `Mutex` (Swift 6 `Synchronization`, iOS 18+/macOS 15+). Raw pointers are not `Sendable`, so the wrapper is declared `@unchecked Sendable` — and the lock is the *only* acceptable justification for that attribute. Every `@unchecked Sendable` in the codebase names the lock that guards it in a comment; one without a lock is a review blocker.
2. **Release in the wrapper's `deinit`, through the lock.** A `nonisolated deinit` may call into the lock; it may not call actor-isolated methods.
3. **Let an `actor` own the wrapper** and expose a typed API. Callers never see the raw pointer.
4. **Copy before release at the C boundary.** When C returns a buffer that is freed on the next call or on handle release, copy it into a Swift-owned `[UInt8]`/`Data` *before* releasing the lock or the handle. Never hand a Swift buffer to C past the call that borrows it (`withUnsafeBytes` scope ends, the pointer is dead).

```swift
import os

/// `@unchecked` is justified solely by `state`: every access to the pointer goes through the lock.
final class MeshHandle: @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<OpaquePointer?>

    init(_ raw: OpaquePointer) {
        state = OSAllocatedUnfairLock(initialState: raw)
    }

    /// Copy-before-release: the C buffer is only valid while we hold the lock.
    func vertices() -> [Float] {
        state.withLock { raw -> [Float] in
            guard let raw else { return [] }
            var count: Int32 = 0
            let ptr = mesh_vertices(raw, &count)        // borrowed, freed by C on next call
            return Array(UnsafeBufferPointer(start: ptr, count: Int(count)))
        }
    }

    deinit {
        // nonisolated by definition; safe because the lock, not an actor, guards the pointer.
        state.withLock { raw in
            if let raw { mesh_free(raw) }
            raw = nil
        }
    }
}

actor MeshStore {
    private var meshes: [UUID: MeshHandle] = [:]

    func load(_ bytes: [UInt8]) throws -> UUID {
        let raw = try bytes.withUnsafeBufferPointer { buf -> OpaquePointer in
            guard let p = mesh_parse(buf.baseAddress, Int32(buf.count)) else { throw MeshError.parse }
            return p
        }
        let id = UUID()
        meshes[id] = MeshHandle(raw)
        return id
    }
}
```

## 9. Memory Management

* **ARC:** Automatic Reference Counting. Avoid retain cycles with `weak`/`unowned`.
* **Closures:** Prefer structured concurrency (`async let`, `TaskGroup`) over escaping closures — structured tasks end with their scope and cannot form cycles. Use `[weak self]` in long-lived escaping closures (delegates, observers, `Timer`, Combine sinks); `[unowned self]` only when the closure provably cannot outlive `self`.
* **Value Types:** Prefer `struct` over `class` when possible.
* **Native handles:** See §8.1 — wrap every C/Metal/file-descriptor handle so release is deterministic and copy-before-release is the only way out of the C boundary.

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

For app targets (iOS/macOS/tvOS/watchOS/visionOS), the `.xcodeproj` is a build artifact, not a source file. Treat a declarative manifest as the source of truth, and set code-signing build settings deliberately so device builds work the first time. There are two compliant paths; pick one per app and record the choice in an ADR.

### 14.0 Choosing the build path: SwiftPM-only vs. generated project

| | **SwiftPM-only** (`Package.swift` is the whole manifest) | **Generated project** (XcodeGen `project.yml` / Tuist `Project.swift`) |
| --- | --- | --- |
| Use when | macOS apps, CLI tools, SwiftUI apps with no asset catalog or entitlements, libraries, plugins | iOS/visionOS apps needing asset catalogs, entitlements, app extensions, multi-target signing, Interface Builder |
| Checked in | `Package.swift`, `Package.resolved` | `project.yml`, `Package.resolved`; `.xcodeproj` gitignored |
| CI build | `swift build -c release -Xswiftc -warnings-as-errors`; `swift test` | `xcodegen generate && xcodebuild -scheme … test` |
| Device run / signing | `xcodebuild -scheme <Target> -destination …` directly against `Package.swift` (Xcode synthesizes the project in memory) | Per §14.2 |
| Formatting gate | `swift format lint --strict` | `swift format lint --strict` |

**SwiftPM-only rules:**

* There is no `.xcodeproj` in the repository and none is generated into it. Opening `Package.swift` in Xcode is the IDE path; the CLI path is `swift build`/`swift test`, and both must stay green.
* Executable app targets declare their resources with `resources: [.process("Resources")]` and read them through `Bundle.module`.
* An `Info.plist` or entitlements that an executable needs are passed via `linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", …])]` **only** in the root package (SwiftPM rejects `unsafeFlags` in dependencies). If the app grows past what `unsafeFlags` can express cleanly, switch to the generated-project path — do not hand-create an `.xcodeproj`.
* Signing for distribution happens outside the manifest (`codesign`/`notarytool` in the release lane), never by checking in a project file.

### 14.1 Project file generation

* **Tool:** Use [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) or [Tuist](https://github.com/tuist/tuist) (`Project.swift`) for any project with more than one target. Hand-maintained `.xcodeproj` files cause merge conflicts and silent setting drift.
* **Source of truth:** `project.yml` (or `Project.swift`) is checked in; the generated `.xcodeproj` is **gitignored**. Never edit build settings in the Xcode UI — regeneration overwrites them.
* **Regenerate before build:** CI and local `make build` targets must run `xcodegen generate` (or `tuist generate`) before invoking `xcodebuild`, so the project file always matches the spec.

### 14.2 Code signing — the rules

These settings are easy to get wrong, and the failure modes are confusing (UI looks correct, device install still fails). Follow these rules:

1. **Set `DEVELOPMENT_TEAM` to the 10-character Apple Developer Team ID.** Team IDs are public identifiers (visible in App Store listings); safe to commit. With `CODE_SIGN_STYLE: Automatic` (the recommended default), an empty `DEVELOPMENT_TEAM` prevents Xcode from resolving a signing identity and the build product ends up unsigned. Manual signing (explicit `PROVISIONING_PROFILE_SPECIFIER` / `CODE_SIGN_IDENTITY`) can still produce a signed device build without `DEVELOPMENT_TEAM`, but if you're using Automatic signing, set it.
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
    SWIFT_VERSION: "<latest stable>"   # match the toolchain (Xcode → Swift version)
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

1. **Inspect the generated `.xcodeproj`, not the UI.** Run `find . -name project.pbxproj -path '*.xcodeproj/*' -exec grep -HE 'DEVELOPMENT_TEAM|CODE_SIGN' {} +` from the repo root — verify `DEVELOPMENT_TEAM` is set and no `CODE_SIGNING_ALLOWED = NO` lines appear. (Avoid relying on a bare `*.xcodeproj/project.pbxproj` glob: it fails silently on nested layouts and on shells that error when the glob has zero matches.)
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

## 15. Build Caches & Cloud-Synced Checkouts

SwiftPM and Xcode write large, churny caches next to the checkout: `.build/` (SwiftPM), `.swiftpm/` (per-package Xcode state), and `DerivedData/` (Xcode). When the checkout lives inside an iCloud Drive, Dropbox, OneDrive, or Google Drive folder, the sync client fights the build system — files vanish mid-compile, `.o` files get `.icloud` placeholders, and incremental builds stall for minutes while thousands of objects upload.

* **Checkouts live outside synced folders.** Clone into `~/src`, `~/code`, or another path the sync client does not watch. If the project *must* live in a synced folder, mark the cache directories as excluded (`.nosync` suffix on macOS iCloud, Dropbox/OneDrive selective sync) — but the simpler rule is to move the checkout.
* **Redirect caches when you cannot move the checkout.** `swift build --scratch-path ~/.cache/swiftpm/<project>` and `xcodebuild -derivedDataPath ~/Library/Developer/Xcode/DerivedData/<project>` keep artifacts out of the synced tree. Put the flags in the `Makefile` so every lane uses them.
* **Gitignore the caches.** `.build/`, `.swiftpm/`, `DerivedData/`, `*.xcuserstate`, and `xcuserdata/` are never committed. `Package.resolved` **is** committed (§1).
* **CI caches by lockfile hash.** Key the `.build/` cache on `hashFiles('Package.resolved')` so a dependency bump invalidates it and nothing else does.
