Design around resources. Use RESTful conventions. Version APIs from the start (`/v1/`).
Error responses: consistent structured JSON with error code, message, and details. Never 200 with error body.
Never expose internal stack traces or DB errors to clients in production.
Expose `/health` (liveness) and `/ready` (readiness) endpoints. Health endpoints are exempt from authentication but must be restricted to internal networks in production.
Validate and sanitize all inputs at the API boundary before processing.
Implement idempotency keys for non-idempotent operations (POST, PATCH).
Apply rate limiting on all public-facing endpoints. Enforce HTTPS. Configure security headers.
Structured logging: include request ID, user ID, operation name, and duration on every log entry.
Emit metrics: request count, latency (p50/p95/p99), and error rate.
Propagate trace context headers (OpenTelemetry or equivalent).
If the service exposes tools to AI agents (MCP / function calling): snake_case wire names matching `^[a-z][a-z0-9_]{0,63}$`, descriptions that state returns and side effects, `writes` flag + `preview` on every mutating tool, approval gate on writes, paginated `list`/`search`, `<untrusted-data>` fencing on external content, read-only sessions by default, audit log per call (arch-10).
