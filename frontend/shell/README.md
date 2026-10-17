# frontend-shell (temporary page)

| Field | Value |
| --- | --- |
| Owning team | Customer Experience Tribe (CXT) |
| Language | Plain JavaScript (ES modules), HTML, CSS (ADR-0018) |
| Server | nginx 1.30 (unprivileged), no database |
| Compose service | `frontend-shell` (profile `frontend`) |
| Networks | `public` |
| Ports (container) | 8080 HTTP |
| Version | 0.1.0 |

## Role

The calculator of AaaS: a keypad (`0`–`9`, `+`, `=`, `C`) and a display
(`CLAUDE.md` 1), served on <http://127.0.0.1/> through the gateway.

`TEMPORARY(P8.15)`: this single plain-JavaScript page stands in for the
single-spa shell (P8.1), the Elm display (P8.2) and the key microfrontends
(P8.3–P8.15), which replace it. The waiting-time counter (P8.17) and the
invoice button (P9.3) arrive with their services.

The page already talks the way the microfrontends will: every key button
publishes `aaas:key-pressed {key}` on `window`, the page publishes
`aaas:clear`, `aaas:task-started {taskId}` and
`aaas:task-finished {taskId, result}` (`CLAUDE.md` 2).

## Behaviour

1. Each session has a random `sessionId`; every accepted key is sent to
   `POST /api/v1/keys` as `{sessionId, key, seq}`, strictly in order, with a
   2 s deadline and up to 3 attempts (`CLAUDE.md` 6.1).
2. `=` (with a non-empty expression) carries a new `Idempotency-Key`; the
   `202 {taskId}` answer starts polling `GET /api/v1/tasks/{taskId}` every
   second (`CLAUDE.md` 3, step 12).
3. The display shows the expression while typing; while waiting, the
   status and `done / total` successor calls; then the result with
   `expression =` above it.
4. `Error` is shown for a `FAILED` task or a task still unknown after 15 s
   (`TEMPORARY(P3.6)`: an expression the parser rejects, such as `2++3`,
   is not reported otherwise); `Unavailable` when a key press could not be
   delivered.
5. While waiting only `C` is accepted. After a result, a digit or `+`
   starts a new calculation; `C` always does. The expression stops at 64
   characters (`aaas.expression.submitted.v1`).

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `GET /`, `/index.html`, `/main.js`, … | in (through the gateway) | Static files |
| HTTP | `GET /health` | in (container only) | `200 {"status":"ok","checks":{}}`; `404` through the gateway |
| HTTP | `GET /metrics` | in (container only) | `frontend_shell_up 1`; `404` through the gateway |
| HTTP | `POST /api/v1/keys` | out (browser) | [expression-assembler](../../services/expression-assembler/README.md) |
| HTTP | `GET /api/v1/tasks/{taskId}` | out (browser) | [ledger API](../../services/ledger/docs/API.md) (`TEMPORARY(P3.3)`) |
| Browser event | `aaas:key-pressed`, `aaas:clear`, `aaas:task-started`, `aaas:task-finished` | in/out | `CLAUDE.md` 2 |

Details: [docs/API.md](docs/API.md).

## Files

| File | Content |
| --- | --- |
| `src/index.html` | Page: display and keypad container |
| `src/style.css` | Layout, light and dark colour schemes |
| `src/main.js` | Entry point: builds the keypad, starts the page logic |
| `src/app.js` | Page logic: event bus, ordered key sending, polling |
| `src/calculator.js` | State machine (pure) |
| `src/api.js` | Public API client with deadline and retries |
| `src/ids.js` | Version 4 UUIDs, also outside a secure context |
| `nginx/default.conf` | Static server, security headers, JSON access log |

There is no build step: the browser loads the ES modules as written.

## Configuration

None: the page uses relative URLs (same origin as the gateway); nginx
listens on 8080.

## Running and testing

```sh
make build-frontend-shell   # image through Compose (root Makefile)
make test-shell             # 19 node:test tests, then HTTP checks of the runtime image
make lint-shell             # Prettier check, ESLint (recommended and JSDoc rules)
make fmt-shell              # format in place with Prettier
make doc-coverage-shell     # JSDoc rules only and a strict JSDoc parse: 100%
make api-docs-shell         # JSDoc HTML to build/api-docs/shell
make logs SVC=frontend-shell
```

After `make up`, open <http://127.0.0.1/> and press `2`, `+`, `3`, `=`.

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
