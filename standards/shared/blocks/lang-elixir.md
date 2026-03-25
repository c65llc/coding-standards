Use Mix for project management (`mix.exs`). Commit `mix.lock`. Elixir 1.15+ / OTP 26+ stable.
Manage packages via Hex (`hex.pm`). Run `mix hex.audit` in CI for vulnerability scanning.
Format with `mix format` (mandatory). Lint with `mix credo --strict`. Type analysis with `mix dialyzer`.
Test with ExUnit (`mix test`). Use `async: true` for stateless tests. Factories via `ex_machina`, mocks via `mox`.
OTP patterns: wrap stateful processes in GenServer, always supervise with Supervisor, use Task for async work.
Pattern matching: prefer function-head dispatch over conditionals. Use `with` for chaining fallible steps.
Pipe operator (`|>`): express sequential transformations; each step does one clear thing.
Naming: `snake_case` functions/variables/atoms/files, `PascalCase` modules. `?` suffix for predicates, `!` for raising variants.
Documentation: `@moduledoc` on every module, `@doc` and `@spec` on every public function, `iex>` doctests for pure functions.
Phoenix: thin controllers, business logic in Contexts, Ecto changesets for all input validation.
Security: secrets via `runtime.exs`/env vars only, Ecto parameterized queries, `mix sobelow` SAST in CI.
