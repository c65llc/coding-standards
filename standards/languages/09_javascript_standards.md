# JavaScript Standards

## 1. Package Management

* **Tool:** `pnpm` preferred, `npm` acceptable. Lock files committed.
* **Version:** ES2022+ features. Use modern syntax.
* **Config:** `.nvmrc` or `.node-version` to pin Node.js version.

## 2. Code Style

* **Formatter:** `prettier` with line length 120. Run via `make fmt`.
* **Linter:** `eslint` with recommended rules. Use `eslint-config-prettier` to avoid conflicts.
* **Type Checking:** Use JSDoc with `@ts-check` or migrate to TypeScript.

### .eslintrc.js

```javascript
module.exports = {
  env: {
    es2022: true,
    node: true,
  },
  extends: ['eslint:recommended', 'prettier'],
  parserOptions: {
    ecmaVersion: 2022,
    sourceType: 'module',
  },
  rules: {
    'no-unused-vars': 'error',
    'no-console': 'warn',
  },
};
```

## 3. Naming Conventions

* **Files:** `kebab-case.js` or `kebab-case.mjs`
* **Classes:** `PascalCase`
* **Variables/Functions:** `camelCase`
* **Constants:** `UPPER_SNAKE_CASE` or `camelCase` with `const`
* **Private:** `_leadingUnderscore` (convention only)

## 4. Project Structure

```
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

## 5. Modern JavaScript

* **ES Modules:** Use `import`/`export`. Avoid CommonJS `require()`.
* **Const/Let:** Always use `const`. Use `let` only when reassignment needed. Never use `var`.
* **Arrow Functions:** Prefer arrow functions for callbacks. Use regular functions for methods.
* **Destructuring:** Use destructuring for objects and arrays.
* **Template Literals:** Use template strings instead of concatenation.

### Example

```javascript
class Email {
  #value;

  constructor(value) {
    if (!/^[^@]+@[^@]+\.[^@]+$/.test(value)) {
      throw new InvalidEmailError(value);
    }
    this.#value = value;
  }

  toString() {
    return this.#value;
  }
}

class Result {
  static success(data) {
    return { success: true, data };
  }

  static failure(error) {
    return { success: false, error };
  }
}
```

## 6. Error Handling

* **Custom Errors:** Extend `Error` class. Use typed error classes.
* **Try-Catch:** Always handle errors. Use `try-catch` for synchronous, `catch()` for promises.
* **Error Context:** Include context in error messages.

```javascript
class DomainError extends Error {
  constructor(message, cause) {
    super(message);
    this.name = this.constructor.name;
    this.cause = cause;
    Error.captureStackTrace(this, this.constructor);
  }
}

class InvalidEmailError extends DomainError {
  constructor(email) {
    super(`Invalid email: ${email}`);
    this.email = email;
  }
}
```

## 7. Testing

* **Framework:** `vitest` or `jest`. Use `@testing-library` for DOM testing.
* **Mocking:** Use framework's built-in mocking. Mock external dependencies.
* **Coverage:** **95% is the absolute minimum for any module.** Target 100% for domain, 95%+ for application and infrastructure.

### Test Structure

```javascript
import { describe, it, expect, vi } from 'vitest';
import { UserService } from './user-service.js';
import { Email } from './domain/email.js';

describe('UserService', () => {
  it('should create user with valid email', () => {
    // Given
    const email = new Email('test@example.com');

    // When
    const user = UserService.createUser(email, 'Test User');

    // Then
    expect(user.email.toString()).toBe('test@example.com');
  });
});
```

## 8. Async/Await

* **Promises:** Use `async`/`await` over `.then()`. Use `Promise.all()` for parallel operations.
* **Error Handling:** Always handle promise rejections. Use `try-catch` with async functions.

```javascript
async function fetchUser(id) {
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
* **Validation:** `zod` for runtime validation
* **State Management:** Framework-specific or `zustand`
* **Logging:** `pino` or `winston`

## 10. Documentation

* **JSDoc:** Use JSDoc comments for public APIs. Generate docs with `jsdoc`.
* **Format:** Use `@param`, `@returns`, `@throws` tags.

```javascript
/**
 * Creates a new user with validated email address.
 *
 * @param {Email} email - Valid email address (must match RFC 5322)
 * @param {string} name - User's full name (non-null, non-empty)
 * @returns {User} New User entity instance
 * @throws {InvalidEmailError} If email format is invalid
 * @example
 * ```js
 * const user = createUser(new Email('test@example.com'), 'John Doe');
 * ```
 */
function createUser(email, name) {
  // Implementation
}
```

## 11. Node.js Specific

* **ES Modules:** Use `.mjs` extension or `"type": "module"` in `package.json`.
* **File System:** Use `fs/promises` for async file operations.
* **Environment Variables:** Use `dotenv` for local development. Validate with `zod`.

## 12. Browser Specific

* **Bundling:** Use `vite`, `esbuild`, or `webpack` for bundling.
* **Polyfills:** Use `core-js` or `@babel/polyfill` for older browsers if needed.
* **Transpilation:** Use `babel` or `swc` for transforming code.

## 13. Best Practices

* **Immutability:** Prefer immutable data structures. Use `Object.freeze()` for constants.
* **Pure Functions:** Write pure functions when possible. Avoid side effects.
* **Single Responsibility:** Functions should do one thing. Keep functions small.
* **Early Returns:** Use early returns to reduce nesting.

