# Elixir Standards

## 1. Project Management

* **Tool:** Mix (`mix`). `mix.exs` defines the project and its dependencies.
* **Version:** Elixir 1.15+ / OTP 26+ (use latest stable).
* **Lock Files:** `mix.lock` is always committed.

## 2. Package Management

* **Registry:** Hex (`hex.pm`). Add packages to `deps/0` in `mix.exs`.
* **Security:** Run `mix hex.audit` in CI to check for vulnerable packages.
* **Private packages:** Use Hex organizations or Git dependencies for private code.

## 3. Code Style

* **Formatter:** `mix format` is mandatory. Commit only formatted code. Add `mix format --check-formatted` to CI.
* **Linter:** Credo (`mix credo --strict`). Fix all issues before merging.
* **Type analysis:** Dialyxir (`mix dialyzer`). Run in CI. Treat all warnings as errors.

### .credo.exs (minimum)

```elixir
%{
  configs: [
    %{
      name: "default",
      strict: true,
      checks: %{
        enabled: [
          {Credo.Check.Design.AliasUsage, []},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Warning.IExPry, []}
        ]
      }
    }
  ]
}
```

## 4. Naming Conventions

* **Modules:** `PascalCase` (e.g., `MyApp.UserService`)
* **Functions and variables:** `snake_case`
* **Atoms:** `:snake_case`
* **Files:** `snake_case.ex` / `snake_case_test.exs`
* **Predicates:** End with `?` (e.g., `valid?/1`)
* **Bang functions:** End with `!` for versions that raise on error (e.g., `get!/1`)
* **Constants:** Use module attributes (`@max_retries 3`), not uppercase variables

## 5. Project Structure

```text
lib/
├── my_app/
│   ├── application.ex       # OTP Application entry point
│   ├── repo.ex              # Ecto Repo (if using database)
│   ├── domain/              # Business logic
│   │   ├── user.ex
│   │   └── user_policy.ex
│   └── service/
│       └── user_service.ex
test/
├── my_app/
│   └── domain/
│       └── user_test.exs
└── test_helper.exs
config/
├── config.exs               # Shared configuration
├── dev.exs
├── test.exs
└── runtime.exs              # Runtime/prod configuration (secrets via env vars)
```

## 6. Pattern Matching

Pattern matching is idiomatic Elixir. Prefer it over conditional chains.

* **Match in function heads** to dispatch on input shape instead of using `if`/`cond` inside a single function.
* **`case`** for local branching on a value.
* **`with`** for chaining multiple pattern-matching steps where any can fail.

```elixir
# Prefer: function head matching
def process(%{status: :active} = user), do: activate(user)
def process(%{status: :inactive} = user), do: deactivate(user)

# Prefer: with for sequential operations
def create_user(attrs) do
  with {:ok, changeset} <- validate(attrs),
       {:ok, user}      <- Repo.insert(changeset),
       :ok              <- send_welcome_email(user) do
    {:ok, user}
  end
end
```

## 7. Pipe Operator

* Use `|>` to express sequential data transformations.
* Each pipe step should do one clear thing.
* Do not start a pipeline with a bare variable on its own line — begin with the data source.

```elixir
def process_order(order) do
  order
  |> validate_items()
  |> calculate_total()
  |> apply_discounts()
  |> charge_customer()
end
```

## 8. OTP Patterns

* **GenServer:** Use for stateful processes. Implement `handle_call/3`, `handle_cast/2`, and `handle_info/2`.
* **Supervisor:** Wrap all long-lived processes in a Supervisor. Choose a restart strategy (`one_for_one`, `one_for_all`, `rest_for_one`).
* **Application:** Define the top-level supervision tree in `MyApp.Application`.
* **Task:** Use `Task` for one-off async work. Use `Task.Supervisor` for dynamic tasks that need fault isolation.
* **Registry:** Use `Registry` for named process lookups instead of global atoms.

```elixir
defmodule MyApp.UserCache do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, %{}, opts)

  def get(pid, key), do: GenServer.call(pid, {:get, key})

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state, key), state}
  end
end
```

## 9. Testing

* **Framework:** ExUnit. Run with `mix test`.
* **Describe blocks:** Group related tests with `describe/2`.
* **Async tests:** Mark modules with `async: true` when tests have no shared state.
* **Factories:** Use `ex_machina` for test data factories instead of raw fixture files.
* **Mocking:** Use `mox` for behaviour-based mocks. Define behaviours for external dependencies.
* **Coverage:** `mix test --cover`. **95% minimum for any module.** Target 100% for domain logic.

```elixir
defmodule MyApp.UserTest do
  use ExUnit.Case, async: true

  describe "validate/1" do
    test "returns :ok for valid attrs" do
      assert {:ok, _user} = MyApp.User.validate(%{email: "test@example.com", name: "Alice"})
    end

    test "returns error for missing email" do
      assert {:error, changeset} = MyApp.User.validate(%{name: "Alice"})
      assert "can't be blank" in errors_on(changeset).email
    end
  end
end
```

## 10. Documentation

* **`@moduledoc`:** Required on every module. Use `@moduledoc false` only for internal modules that are implementation details.
* **`@doc`:** Required on every public function. Describe what it does, its arguments, and its return values.
* **`@spec`:** Required on every public function. Dialyzer uses specs for analysis.
* **Examples:** Include `## Examples` with `iex>` doctests in `@doc` for pure functions.

```elixir
defmodule MyApp.User do
  @moduledoc """
  Domain type and business rules for user management.
  """

  @doc """
  Validates user attributes and returns a changeset.

  ## Examples

      iex> MyApp.User.validate(%{email: "test@example.com", name: "Alice"})
      {:ok, %MyApp.User{}}

  """
  @spec validate(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def validate(attrs), do: # ...
end
```

## 11. Phoenix Conventions

When using Phoenix:

* **Contexts:** Group domain logic into Phoenix Contexts (`MyApp.Accounts`, `MyApp.Orders`). Controllers call context functions, never Ecto directly.
* **Controllers:** Thin — delegate to context functions. No business logic in controllers.
* **LiveView:** Use `assign/3` for state. Extract reusable UI into function components (`Phoenix.Component`).
* **PubSub:** Use `Phoenix.PubSub` for broadcasting events across processes.
* **Channels:** Use Phoenix Channels for bidirectional real-time communication.
* **Plugs:** Use `Plug` for shared request pipeline logic (authentication, logging, etc.).

## 12. Security

* **Secrets:** Never hardcode secrets. Use `config/runtime.exs` with `System.fetch_env!/1`.
* **SQL injection:** Use Ecto parameterized queries exclusively. Never interpolate input into query strings.
* **XSS:** Phoenix templates auto-escape HTML by default. Use `raw/1` only when output is known-safe.
* **CSRF:** Phoenix includes CSRF protection by default. Do not disable it.
* **Input validation:** Use Ecto changesets to validate and cast all external input.
* **SAST:** Run `mix credo --strict` and `mix sobelow` (Phoenix security-focused SAST) in CI.
* **Dependency scanning:** Run `mix hex.audit` in CI.
* See [sec-01_security_standards.md](../security/sec-01_security_standards.md) for the complete banned-functions list with language-specific examples.
