<!-- Kept in sync by hand with the page (src/) and the contracts it uses;
     the browser event bus has no machine-readable contract yet (Phase 8).
     The native API documentation (JSDoc) is published in the portal by
     `make docs`. -->
# API Reference — `frontend-shell`

| Field | Value |
| --- | --- |
| Document | API Reference |
| Component | `frontend-shell` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Service Version | 0.1.0 |

## 1. HTTP (port 8080)

| Method | Path | Description | Response |
| --- | --- | --- | --- |
| `GET` | `/` (`/index.html`) | The calculator page | `200 text/html` |
| `GET` | `/style.css`, `/favicon.svg`, `/main.js`, `/app.js`, `/calculator.js`, `/api.js`, `/ids.js` | Its resources | `200` |
| `GET` | `/health` | Liveness (container only) | `200 {"status":"ok","checks":{}}`; `404` for requests forwarded by the gateway |
| `GET` | `/metrics` | Prometheus metrics (container only) | `200 text/plain; version=0.0.4` with `frontend_shell_up 1`; `404` through the gateway |

Any other path is `404` (nginx error page). Every answer carries
`Content-Security-Policy` (`default-src 'self'`, no frames, no inline
code), `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` and
`Cache-Control: no-cache`.

## 2. Calls made by the page (from the browser)

| Method | Path | When | Contract |
| --- | --- | --- | --- |
| `POST` | `/api/v1/keys` | Every accepted key, in order; `=` with `Idempotency-Key` | `{sessionId, key, seq}` → `204`, or `202 {taskId}` for `=` (services/expression-assembler/README.md) |
| `GET` | `/api/v1/tasks/{taskId}` | Every second after `=` until `RECORDED` or `FAILED` | `200 {taskId, status, a, b, progress, result?}` or `404` (services/ledger/docs/API.md) |

Deadline 2 s per request; a key press is tried up to 3 times (network
error, timeout, `5xx`).

## 3. Browser events (`window`, `CLAUDE.md` 2)

| Event | `detail` | Published by | When |
| --- | --- | --- | --- |
| `aaas:key-pressed` | `{ key }` | each key button | On click |
| `aaas:clear` | `null` | the page | On `C` |
| `aaas:task-started` | `{ taskId }` | the page | `=` answered `202` |
| `aaas:task-finished` | `{ taskId, result }` | the page | The task is `RECORDED` |

## 4. Events (Redpanda)

None: the page does not use the event bus of the services.
