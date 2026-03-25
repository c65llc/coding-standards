Use `pub`. `pubspec.yaml` for all dependencies. Pin versions for production. Dart 3.0+ (null safety required).
Format with `dart format`. Analyze with `dart analyze` + `analysis_options.yaml`. No implicit `dynamic`.
Use nullable types (`String?`) with null-aware operators. Use `!` only when safe.
Prefer `final` over `var`. Use `const` constructors when possible. Use `sealed class` for ADTs/Result types.
Use `record` (Dart 3.0+) for value objects. Use `freezed` for immutable data with code generation.
Naming: `snake_case.dart` files, `PascalCase` classes/enums, `camelCase` variables/functions, `_leadingUnderscore` library-private.
Test with `test` package. Mock with `mockito` + `@GenerateMocks`. 95% coverage minimum, 100% for domain.
Use `Future<T>` for async; `Stream<T>` for reactive data. Prefer `async`/`await` over `.then()`.
Flutter: use `riverpod` or `bloc` for state management. Prefer `const` widgets. Avoid `setState` for business logic.
Security: GitHub Dependabot for pub. Use `dart:math Random.secure()` for security contexts, not `Random()`.
