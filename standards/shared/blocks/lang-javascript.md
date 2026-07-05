Use `pnpm` (preferred) or `npm`. Commit lock files verbatim — they are generated artifacts, never hand-formatted. Pin Node.js version in `.nvmrc`.
Pin the package manager: set an exact `packageManager` field in `package.json` and add `.npmrc` with `manage-package-manager-versions=true` so local pnpm self-switches to the pinned version (byte-identical to CI). CI installs from the lockfile without updating it (`pnpm install --frozen-lockfile`, or `npm ci` for npm).
Format with `prettier` (line length 120). Lint with `eslint` + `eslint-config-prettier`. Every repo ships a `.prettierignore` excluding lockfiles (`pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`).
Use ES modules (`import`/`export`). Avoid CommonJS `require()`.
Always `const`. Use `let` only when reassignment needed. Never `var`.
Use JSDoc + `@ts-check` for type safety, or migrate to TypeScript.
Use private class fields (`#field`) for encapsulation.
Naming: `camelCase` variables/functions, `PascalCase` classes, `kebab-case` files, `UPPER_SNAKE_CASE` constants.
Test with `vitest` or `jest`. 95% coverage minimum, 100% for domain.
Security: `eslint-plugin-security` and `pnpm audit` in CI. Banned: `eval()`, `Function()`, `setTimeout(string)`, `document.write()`. Use `crypto.randomUUID()` for security contexts, not `Math.random()`.
