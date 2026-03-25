# Go Standards

## 1. Package Management

* **Tool:** Go modules (`go mod`). `go.mod` and `go.sum` are both committed.
* **Version:** Go 1.21+ (use latest stable).
* **Dependencies:** Use `go get` to add dependencies. Keep `go.sum` in sync.

## 2. Code Style

* **Formatter:** `gofmt` is mandatory. Run automatically via `goimports` (which also manages import groups).
* **Linter:** `golangci-lint`. Run via `golangci-lint run` in CI. Treat all warnings as errors.
* **Vet:** `go vet ./...` is required in CI.

### .golangci-lint.yml (minimum)

```yaml
linters:
  enable:
    - errcheck
    - gosimple
    - govet
    - ineffassign
    - staticcheck
    - unused
    - goimports
    - revive
```

## 3. Naming Conventions

* **Files:** `snake_case.go`
* **Packages:** Short, lowercase, no underscores (e.g., `httputil`, not `http_util`)
* **Exported (public) identifiers:** `PascalCase`
* **Unexported (private) identifiers:** `camelCase`
* **Constants:** `PascalCase` (exported) or `camelCase` (unexported) — Go does not use `ALL_CAPS`
* **Interfaces:** Prefer single-method interfaces named by the method plus `-er` suffix (e.g., `Reader`, `Stringer`)
* **Acronyms:** Keep uppercase: `HTTPClient`, `URLParser`, `userID`

## 4. Project Layout

```text
cmd/
├── myapp/
│   └── main.go          # Entry points, one per binary
internal/
├── domain/              # Business logic not importable outside module
│   ├── user.go
│   └── user_test.go
├── service/
│   └── user_service.go
pkg/
├── httputil/            # Reusable packages safe for external import
│   └── client.go
```

* `cmd/` — binary entry points only; minimal logic.
* `internal/` — code that must not be imported by other modules.
* `pkg/` — packages intended for external use; keep stable.
* Avoid deep nesting. Flat packages are idiomatic Go.

## 5. Error Handling

Go uses explicit error returns. There are no exceptions.

* **Always check errors.** Never use `_` for an error return without a documented reason.
* **Wrap errors** with `fmt.Errorf("context: %w", err)` to preserve the error chain.
* **Sentinel errors:** Declare with `var ErrNotFound = errors.New("not found")`. Use `errors.Is` to check.
* **Error types:** Use a struct type implementing `error` when callers need to inspect error fields.
* **Panics:** Reserved for programmer errors (e.g., invalid index). Never panic for expected runtime errors.

```go
func findUser(ctx context.Context, id string) (*User, error) {
    user, err := db.QueryUser(ctx, id)
    if err != nil {
        return nil, fmt.Errorf("findUser %s: %w", id, err)
    }
    if user == nil {
        return nil, ErrNotFound
    }
    return user, nil
}
```

## 6. Interfaces

Go interfaces are satisfied implicitly — no `implements` keyword.

* **Define interfaces at the consumer, not the producer.** The package that uses an interface declares it.
* **Keep interfaces small.** Prefer one or two methods. Compose larger interfaces from smaller ones.
* **Accept interfaces, return concrete types** (from functions/constructors).

```go
// In the service package (consumer), not the storage package (producer)
type UserStore interface {
    FindByID(ctx context.Context, id string) (*User, error)
    Save(ctx context.Context, user *User) error
}
```

## 7. Concurrency

* **Goroutines:** Always document the lifecycle of every goroutine. Know when it exits.
* **Channels:** Prefer channels for communication; use `sync` primitives for state protection.
* **Context:** Pass `context.Context` as the first argument to functions that can block or be cancelled.
* **WaitGroups:** Use `sync.WaitGroup` to wait for a group of goroutines to complete.
* **Race detector:** Run `go test -race ./...` in CI. All races must be fixed.
* **Avoid goroutine leaks.** Use `context` cancellation or `done` channels to signal goroutines to stop.

```go
func processAll(ctx context.Context, items []Item) error {
    g, ctx := errgroup.WithContext(ctx)
    for _, item := range items {
        item := item // capture loop variable
        g.Go(func() error {
            return process(ctx, item)
        })
    }
    return g.Wait()
}
```

## 8. Testing

* **Framework:** Built-in `testing` package. Run with `go test ./...`.
* **Table-driven tests:** Preferred for functions with multiple input/output cases.
* **Test files:** `_test.go` suffix in the same package (white-box) or `_test` package suffix (black-box).
* **Mocking:** Use interface-based test doubles. `github.com/stretchr/testify/mock` or hand-written fakes.
* **Assertions:** `github.com/stretchr/testify/assert` and `require` for cleaner assertions.
* **Coverage:** `go test -cover ./...`. **95% minimum for any package.** Target 100% for domain logic.

```go
func TestFindUser(t *testing.T) {
    tests := []struct {
        name    string
        id      string
        want    *User
        wantErr error
    }{
        {"found", "123", &User{ID: "123"}, nil},
        {"not found", "999", nil, ErrNotFound},
    }
    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            got, err := findUser(context.Background(), tc.id)
            require.ErrorIs(t, err, tc.wantErr)
            assert.Equal(t, tc.want, got)
        })
    }
}
```

## 9. Documentation

* **Exported identifiers** must have a godoc comment starting with the identifier name.
* **Package comment:** Every package has a `// Package <name> ...` comment in one file.
* **Format:** Plain text. `godoc` renders it — no Markdown.

```go
// Package user provides domain types and business rules for user management.
package user

// User represents an authenticated member of the system.
type User struct {
    ID    string
    Email string
}

// FindByEmail returns the user with the given email address,
// or ErrNotFound if no such user exists.
func FindByEmail(ctx context.Context, email string) (*User, error) {
    // ...
}
```

## 10. Dependencies

### Common Packages

* **HTTP routing:** `net/http` stdlib + `github.com/go-chi/chi` or `github.com/gin-gonic/gin`
* **Database:** `database/sql` with `github.com/jackc/pgx` (Postgres) or `gorm.io/gorm`
* **Migrations:** `github.com/golang-migrate/migrate`
* **Config:** `github.com/spf13/viper` or `github.com/caarlos0/env`
* **Logging:** `log/slog` (stdlib, Go 1.21+) or `go.uber.org/zap`
* **Testing:** `github.com/stretchr/testify`
* **Concurrency helpers:** `golang.org/x/sync/errgroup`

## 11. Performance

* **Preallocate slices** when length is known: `make([]T, 0, n)`.
* **Profile before optimizing.** Use `go tool pprof` with CPU and heap profiles.
* **Avoid premature optimization.** Write clear code first; profile in production-like conditions.
* **String building:** Use `strings.Builder` instead of repeated concatenation.

## 12. Security

* **Input validation:** Validate and sanitize all external input. Use `html/template` (not `text/template`) for HTML output to prevent XSS.
* **SQL injection:** Use parameterized queries exclusively. Never interpolate user input into SQL strings.
* **SAST:** Run `golangci-lint` with `gosec` enabled in CI (`github.com/securego/gosec`).
* **Dependency scanning:** Run `govulncheck ./...` in CI (`golang.org/x/vuln/cmd/govulncheck`).
* **`unsafe` package:** Do not use `unsafe` unless absolutely necessary. Document every usage with the invariant that makes it safe.
* **Cryptography:** Use `crypto/rand` for random values. Never use `math/rand` for security purposes.
* See [sec-01_security_standards.md](../security/sec-01_security_standards.md) for the complete banned-functions list with language-specific examples.
