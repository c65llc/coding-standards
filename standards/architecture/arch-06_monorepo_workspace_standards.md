# Monorepo & Workspace Standards

These standards apply to repositories that host multiple packages, apps, or
toolchains in a single tree (pnpm/npm workspaces, Cargo workspaces, Gradle
multi-project builds, Go modules, etc.). They complement the Clean Architecture
layering in [core-standards.md](../shared/core-standards.md) — that describes how
*layers* depend on each other; this describes how *workspace members* are built,
checked, and kept from drifting apart.

## 1. Workspace Layout

* A single repository MAY contain multiple workspace members: shared libraries,
  deployable apps, and tools. Group them by kind (`packages/`, `apps/`,
  `crates/`, `tools/`) so the dependency direction is visible from the path.
* Each member owns its manifest (`package.json`, `Cargo.toml`, `build.gradle`)
  and its own build/test/lint pipeline. The root orchestrates members; it does
  not reach inside them.
* Shared business logic lives in inner members (libraries); deployable apps are
  outer members that compose libraries. Apps MUST NOT import from one another —
  extract the shared part into a library instead.

## 2. Multiple Toolchains Are Kept Separate

A repo may host more than one language toolchain (e.g. a JS/TS workspace built
with pnpm + a task runner, and a Rust workspace built with cargo).

* **Keep the toolchains deliberately separate.** Do not make one task runner
  orchestrate another language's build. A JS task graph should not invoke
  `cargo`, and vice versa — each has its own dependency graph, cache, and CI gate.
* Provide one `make` entry point per toolchain gate (`make ci-js`, `make ci-rust`)
  and a top-level `make ci` that runs both, so a contributor never has to know
  which toolchain a change touched.
* Document the split in `CONTRIBUTING.md`: which directories belong to which
  toolchain, and which command gates each.

## 3. Per-Member Pipeline Ownership

* **Each member owns its scope, not its own style.** Shared style/config
  (formatter options, lint rules, TS compiler options) lives in a single root
  config that members inherit or *extend* — never fork. A member may extend the
  root config to add a member-specific plugin (e.g. an Astro or Vue parser) but
  MUST NOT override shared options, or the options silently drift between members.
* A member MAY own its own *ignore* set (e.g. `.prettierignore`,
  `.eslintignore`) because the generated/vendored paths it excludes are genuinely
  member-specific. When adding one, copy the closest sibling's list rather than
  inventing a new shape, so the only differences are the ones that member needs.
* CI runs each member's own check over its own tree. A repo-wide check at the
  root covers shared config and any member without its own gate. Together they
  must leave no file unchecked.

### Verify with the member's own gate

A passing root-level or aggregated check is **not** sufficient evidence that a
member is green. Before pushing a change to a member, run that member's full
local gate (`make ci` from inside the member, or `<runner> --filter <member> ci`)
— the member's gate is the authoritative one CI reproduces.

## 4. Run the Build, Not Just the Typecheck

In many workspaces the per-member `typecheck` (e.g. `tsc --noEmit`) and the CI
`build` (e.g. `tsc -b` with project references) check **different file sets**.
The build is usually the stricter of the two:

* `typecheck` configs commonly **exclude test files**; the project-reference
  build **includes** them.
* Therefore a change that widens a shared interface can pass `typecheck` locally
  yet fail CI `build`, because every test double / inline fake of that interface
  now fails to compile.

**Rules:**

* When you widen or change a shared interface (a port, a trait, a public type),
  grep the *whole* workspace for every implementer — including object-literal
  fakes annotated `: TheInterface`, not just `class X implements Y` — and update
  them all.
* Run the member's `build` (or `make ci`), not just `typecheck`, before pushing.
  Treat "typecheck + lint + test all pass" as insufficient until the build is green.

## 5. Path & Alias Resolution Must Be Complete

When a member maps a package to a path alias (in `tsconfig`, a bundler config, a
test-runner config, etc.), a **bare-package alias shadows unlisted subpaths**.
Mapping `@scope/pkg` does not automatically map `@scope/pkg/sub` — the subpath
silently resolves somewhere else (or fails only in one tool).

**Rules:**

* List **every** subpath alias a member imports, in **every** resolver that
  member uses (the bundler config, the test-runner config, and the typechecker
  config must agree). A subpath that resolves in the bundler but not the
  typechecker is a latent break.
* When you add a new subpath import, add its alias to all resolvers in the same
  change. When copying a member's alias map to a new member, copy it whole.
* Prefer the package manager's native workspace resolution over hand-maintained
  alias maps where possible; reserve aliases for cases the resolver can't cover.

## 6. Generated & Committed Artifacts

Some workspaces commit build outputs that are derived from source (e.g.
WASM/`.d.ts` bundles, generated clients, protobuf stubs) and gate CI on
"the committed artifact matches a fresh rebuild" (`git diff --exit-code` after
regenerating).

* These artifacts MUST be regenerated and committed whenever their source — or a
  **dependency that affects codegen output** — changes. A dependency bump can
  change generated bytes even with no source edit.
* **An incremental rebuild over a warm cache can reproduce stale output** and
  show no drift locally, then fail the CI gate. Reproduce the gate with a *clean*
  build (`cargo clean`, clear the codegen cache) before trusting a "no drift"
  result.
* Pin the codegen toolchain (compiler version, codegen plugin version) so the
  output is deterministic across machines and matches the CI runner.

## 7. Workspace Dependency Hygiene

* No circular dependencies between members. Enforce with a tool
  (`madge`, `cargo-deny`/`cargo tree`, `dependency-cruiser`) in CI.
* Align shared dependency versions across members — a single version of each
  third-party library per workspace, hoisted where the package manager supports
  it. Divergent versions cause duplicate bundles and subtle behavior differences.
* Commit a single lock file per toolchain at the workspace root. Install from the
  lock in CI and in fresh worktrees (see
  [proc-04_agent_workflow_standards.md](../process/proc-04_agent_workflow_standards.md)
  § Worktree Hygiene).
