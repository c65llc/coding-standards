Use `pnpm` (preferred) or `npm`. Commit lock files. Pin Node.js version in `.nvmrc`.
Format with `prettier` (line length 120). Lint with `eslint` + `eslint-config-prettier`.
Use ES modules (`import`/`export`). Avoid CommonJS `require()`.
Always `const`. Use `let` only when reassignment needed. Never `var`.
Use JSDoc + `@ts-check` for type safety, or migrate to TypeScript.
Use private class fields (`#field`) for encapsulation.
Naming: `camelCase` variables/functions, `PascalCase` classes, `kebab-case` files, `UPPER_SNAKE_CASE` constants.
Test with `vitest` or `jest`. 95% coverage minimum, 100% for domain.
Security: `eslint-plugin-security` and `pnpm audit` in CI. Banned: `eval()`, `Function()`, `setTimeout(string)`, `document.write()`. Use `crypto.randomUUID()` for security contexts, not `Math.random()`.
