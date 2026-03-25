Use `pnpm` (preferred) or `npm`. Commit lock files. TypeScript 5.0+ with strict mode.
Format with `prettier` (line length 120). Lint with `eslint` + `@typescript-eslint`. Run `tsc --noEmit` in CI.
No `any`; use `unknown` when type is uncertain. Explicit types on public APIs; infer locally.
Use `Partial<T>`, `Pick<T>`, `Omit<T>`, `Record<K, V>` utility types.
ES modules (`import`/`export`). Avoid `require()`. Use `index.ts` barrel exports selectively.
Use `async`/`await` over `.then()`. Always handle promise rejections.
Naming: `camelCase` variables/functions, `PascalCase` classes/interfaces/types, `kebab-case` files, `UPPER_SNAKE_CASE` constants.
Test with `vitest` or `jest`. 95% coverage minimum, 100% for domain.
Extend `Error` with typed domain errors. Use `Result<T>` pattern for functional error handling.
Security: `eslint-plugin-security` and `pnpm audit` in CI. Banned: `eval()`, `Function()`, `setTimeout(string)`, `document.write()`. Use `crypto.randomUUID()` for security contexts.
