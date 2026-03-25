# Role: Service / API

Design around resources. Use RESTful conventions. Version APIs from the start (`/v1/`).
Error responses: consistent structured JSON with error code, message, and details. Never 200 with error body.
Never expose internal stack traces or DB errors to clients in production.
Expose `/health` (liveness) and `/ready` (readiness) endpoints. No authentication required on health endpoints.
Validate and sanitize all inputs at the API boundary before processing.
Implement idempotency keys for non-idempotent operations (POST, PATCH).
Apply rate limiting on all public-facing endpoints. Enforce HTTPS. Configure security headers.
Structured logging: include request ID, user ID, operation name, and duration on every log entry.
Emit metrics: request count, latency (p50/p95/p99), and error rate.
Propagate trace context headers (OpenTelemetry or equivalent).
