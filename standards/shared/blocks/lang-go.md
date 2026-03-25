Use Go modules (`go mod`). Commit both `go.mod` and `go.sum`. Go 1.21+ stable.
Format with `goimports` (superset of `gofmt`). Lint with `golangci-lint run` — treat warnings as errors.
Run `go vet ./...` and `go test -race ./...` in CI.
Error handling is explicit: always check returned errors; wrap with `fmt.Errorf("context: %w", err)`. No panics for expected errors.
Interfaces are satisfied implicitly. Define interfaces at the consumer. Accept interfaces, return concrete types. Keep interfaces small (one or two methods).
Goroutines: document lifecycle, use `context.Context` for cancellation, detect races with `-race`. Use `errgroup` for parallel work.
Project layout: `cmd/` for entry points, `internal/` for private packages, `pkg/` for reusable public packages.
Naming: `camelCase` unexported, `PascalCase` exported; no `ALL_CAPS` constants; short lowercase package names.
Godoc: every exported identifier has a comment starting with its name; every package has a package comment.
Security: `gosec` linter in CI, `govulncheck` for dependency scanning, `crypto/rand` for randomness, parameterized queries only.
