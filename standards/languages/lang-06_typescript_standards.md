# TypeScript Standards

## 1. Package Management

* **Tool:** `pnpm` preferred, `npm` acceptable. Lock files committed. Pin the package manager via `packageManager` (Corepack).
* **Runtime pinning + ENFORCEMENT:** Pin the Node version (`.nvmrc` + `engines.node`, and `.tool-versions` for asdf/mise). Pinning alone is not enough — **enforce** it so a wrong runtime fails fast with an actionable message instead of a cryptic native-build error: set `engine-strict=true` in `.npmrc` and/or add a `preinstall` guard that compares the active runtime to the pin. (Observed failure: a project on the wrong Node major hit an opaque `node-gyp` failure building a native dependency on every install until the runtime was switched by hand.)
* **Version:** TypeScript 5.0+. Use strict mode.
* **Config:** `tsconfig.json` with strict compiler options.
* **Age Gate:** Do not adopt any npm package version published less than 3 days ago. Verify publish date via npm registry API before upgrading. See `sec-01` §5 for exceptions.

## 2. Code Style

* **Formatter:** `prettier` with line length 120. Run via `make fmt`.
* **Linter:** `eslint` with TypeScript plugin. Use `@typescript-eslint` rules.
* **Type Checker:** `tsc --noEmit` in CI. No `any` without explicit justification.

### tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  }
}
```

## 3. Naming Conventions

* **Files:** `kebab-case.ts` or `kebab-case.tsx`
* **Classes/Interfaces/Types:** `PascalCase`
* **Variables/Functions:** `camelCase`
* **Constants:** `UPPER_SNAKE_CASE` or `camelCase` with `const`
* **Private:** `_leadingUnderscore` (convention only, not enforced)

## 4. Project Structure

```text
src/
├── domain/
│   ├── entities/
│   └── value-objects/
├── application/
│   ├── use-cases/
│   └── interfaces/
└── infrastructure/
    └── repositories/
```

## 5. Type System

* **Strict Mode:** Always enabled. No `any`, `unknown` preferred over `any`.
* **Type Inference:** Let TypeScript infer types when obvious. Explicit types for public APIs.
* **Generics:** Use generics for reusable code. Use constraints with `extends`.
* **Utility Types:** Leverage `Partial<T>`, `Pick<T>`, `Omit<T>`, `Record<K, V>`.

### Example

```typescript
interface Repository<T> {
  findById(id: string): Promise<T | null>;
  save(entity: T): Promise<void>;
}

type Result<T> = 
  | { success: true; data: T }
  | { success: false; error: Error };

class Email {
  private constructor(private readonly value: string) {}
  
  static create(value: string): Email {
    if (!/^[^@]+@[^@]+\.[^@]+$/.test(value)) {
      throw new InvalidEmailError(value);
    }
    return new Email(value);
  }
  
  toString(): string {
    return this.value;
  }
}
```

## 6. Error Handling

* **Custom Errors:** Extend `Error` class. Use typed error classes.
* **Result Pattern:** Use `Result<T>` type for functional error handling.
* **Async Errors:** Use `Promise<T>` with proper error handling.

```typescript
class DomainError extends Error {
  constructor(message: string, public readonly cause?: Error) {
    super(message);
    this.name = this.constructor.name;
    Error.captureStackTrace(this, this.constructor);
  }
}

class InvalidEmailError extends DomainError {
  constructor(public readonly email: string) {
    super(`Invalid email: ${email}`);
  }
}
```

## 7. Testing

* **Framework:** `vitest` or `jest`. Use `@testing-library` for component tests.
* **Mocking:** `vitest` built-in mocking or `jest.mock()`. Mock external dependencies.
* **Coverage:** **95% is the absolute minimum for any module.** Target 100% for domain, 95%+ for application and infrastructure.

### Test Structure

```typescript
import { describe, it, expect, vi } from 'vitest';
import { UserService } from './user-service';
import { Email } from './domain/email';

describe('UserService', () => {
  it('should create user with valid email', () => {
    // Given
    const email = Email.create('test@example.com');
    
    // When
    const user = UserService.createUser(email, 'Test User');
    
    // Then
    expect(user.email.toString()).toBe('test@example.com');
  });
});
```

### Test Quality — Anti-Brittleness

Tests must fail on real regressions, not on incidental details. Each rule below maps to an observed false failure that cost debugging time:

* **Don't assert on raw source text** (CSS/markup strings). A regex over a stylesheet is fragile (e.g. one that "checked for an outline" actually matched whitespace and blocked a valid fix). Assert rendered behavior, or use visual-regression snapshots for appearance.
* **No test-only markup.** Don't add DOM attributes/elements that exist solely so a test can assert them. Query by role/text/label, or by an intentional, app-used hook.
* **Make formatted output deterministic.** Don't assert on locale/timezone-dependent display strings (e.g. `Intl.DateTimeFormat(undefined, …)` — passes only under one locale). Pin the locale/timezone, or assert against a stable `data-*` value rather than the localized text.
* **Scope queries to a container.** When two components render similar elements (e.g. two sets of date buttons), a document-wide query collides and gives false positives/negatives. Use `within(region)` / role-scoped queries.

* **Promises:** Use `async`/`await` over `.then()`. Use `Promise.all()` for parallel operations.
* **Error Handling:** Always handle promise rejections. Use `try-catch` with async functions.

```typescript
async function fetchUser(id: string): Promise<User> {
  try {
    const user = await userRepository.findById(id);
    if (!user) {
      throw new UserNotFoundException(id);
    }
    return user;
  } catch (error) {
    if (error instanceof DomainError) {
      throw error;
    }
    throw new UserFetchError(`Failed to fetch user: ${id}`, error);
  }
}
```

## 9. Dependencies

### Common Libraries

* **HTTP:** `axios` or `fetch` (native)
* **Validation:** `zod` for runtime validation and type inference
* **State Management:** `zustand`, `redux-toolkit`, or framework-specific
* **Logging:** `pino` or `winston`

## 10. Documentation

* **JSDoc:** Use JSDoc comments for public APIs. Generate docs with `typedoc`.
* **Format:** Use `@param`, `@returns`, `@throws` tags.

```typescript
/**
 * Creates a new user with validated email address.
 *
 * @param email - Valid email address (must match RFC 5322)
 * @param name - User's full name (non-null, non-empty)
 * @returns New User entity instance
 * @throws {InvalidEmailError} If email format is invalid
 * @example
 * ```ts
 * const user = createUser(Email.create('test@example.com'), 'John Doe');
 * ```
 */
function createUser(email: Email, name: string): User {
  // Implementation
}
```

## 11. Module System

* **ES Modules:** Use `import`/`export`. Avoid `require()`.
* **Barrel Exports:** Use `index.ts` for public API. Re-export selectively.
* **Path Aliases:** Configure path aliases in `tsconfig.json` for clean imports.

## 12. Framework-Specific

* **React:** Use functional components with hooks. Prefer `useState`, `useEffect`, `useCallback`.
* **Node.js:** Use ES modules. Leverage `async`/`await` for I/O operations.
* **Build Tools:** Use `vite`, `esbuild`, or `tsup` for bundling.

## 13. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Use `eslint-plugin-security` in ESLint config.
- **Dependency scanning:** Run `pnpm audit` (preferred), `npm audit`, or `yarn audit` in CI.
- **Secrets scanning:** Use `detect-secrets` as a pre-commit hook.
- **Banned functions:** See [sec-01_security_standards.md](../security/sec-01_security_standards.md) for the complete banned-functions list with language-specific examples.
- **Secure random:** Use `crypto.randomUUID()` or `crypto.getRandomValues()`, not `Math.random()`, for security contexts.
