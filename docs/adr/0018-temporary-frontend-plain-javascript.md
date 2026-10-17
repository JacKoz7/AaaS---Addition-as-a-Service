# ADR-0018: frontend-shell — temporary plain-JavaScript page served by unprivileged nginx, talking over the browser event bus

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-17 |
| Deciders | Customer Experience Tribe (CXT), Platform Enablement Guild (PEG) |
| Step | P1.8 |

## Context

Step P1.8 needs a page on which a user can press `2`, `+`, `3`, `=` and see
`5`, before the single-spa shell (P8.1) and the sixteen microfrontends of
Phase 8 exist. `CLAUDE.md` asks for "one page in plain JS" marked
`TEMPORARY(P8.x)`; P8.15 removes it. The gateway already routes `/` to
`frontend-shell:8080` (ADR-0012). Every element is an nginx container on the
`public` network (`CLAUDE.md` 2, 6.2). The documentation rules of 6.5 apply
(`eslint-plugin-jsdoc`, require-jsdoc everywhere, for JavaScript).

Open questions: how the page is structured so that it can be tested and so
that Phase 8 can take it apart, how it is served, which tools enforce
format, lint and documentation, and how its health and metrics endpoints
coexist with the gateway's catch-all route.

## Decision

- **No framework, no build step.** Plain ES modules loaded by the browser as
  written: `calculator.js` (pure state machine), `api.js` (public API client
  with injected `fetch`), `ids.js` (UUIDv4), `app.js` (wiring with injected
  DOM elements, event bus, timers) and a small `main.js` entry point. All but
  `main.js` run unchanged under Node.js, so the logic is tested with
  `node:test` and no browser.
- **Browser event bus now.** The keypad publishes `aaas:key-pressed {key}` and
  the page publishes `aaas:clear`, `aaas:task-started` and
  `aaas:task-finished` on `window`, exactly the events of `CLAUDE.md` 2, so
  that Phase 8 replaces parts of the page without changing the protocol.
- **Key presses in order.** Keys are sent one after another (a promise
  queue), each with up to 3 attempts of 2 s; retries are safe because the
  expression assembler accepts the same key at the same `seq` again and the
  same `Idempotency-Key` returns the same task. While a task runs only `C` is
  accepted; after a result a digit or `+` starts a new session.
- **Status by polling** every second (`CLAUDE.md` 3, step 12). A task still
  unknown after 15 s is shown as `Error` (`TEMPORARY(P3.6)`: the parser's
  rejection of `2++3` is not reported back until the dead-letter service).
- **UUIDs from `crypto.getRandomValues`.** `crypto.randomUUID` exists only in
  secure contexts; a headless-browser test through `http://gateway:8000/`
  showed the page failing there, as it would when opened by host name from
  another machine. Version 4 UUIDs are built from random bytes instead.
- **Serving.** `nginxinc/nginx-unprivileged:1.30.6-alpine3.24` (UID 101,
  port 8080), 90 MB image, 7 MiB of RAM. Security headers: a strict
  `Content-Security-Policy` (`'self'` only, no inline code, no frames),
  `nosniff`, `no-referrer`, `Cache-Control: no-cache` (no build step adds
  content hashes). The access log is one JSON line per request with the
  fields of 6.1; nginx's own error log stays plain text on stderr.
- **Health and metrics behind the catch-all route.** The gateway forwards
  every unmatched path, including `/health` and `/metrics`, to this
  container. Requests that carry `X-Forwarded-For` (set by the gateway) get
  `404` on those two paths; the Compose health check and Prometheus reach
  the container directly. `/metrics` exposes `frontend_shell_up 1`: nginx has
  no Prometheus exporter, and a static page has nothing else to measure.
- **Tooling** (Node.js 24 LTS toolchain image, exact versions in
  `package-lock.json`): Prettier (print width 120), ESLint 10 with the
  recommended rules and `eslint-plugin-jsdoc`. The documentation rules
  require a JSDoc block on every function declaration, top-level
  declaration and export, with a description, `@since`, every parameter,
  the return value, an `@example` on exported functions, and the text
  fields `Description:` and `Owner:` (plus `Business Justification:`,
  `Errors:`, `Side Effects:`, `Complexity:` and `Thread Safety:` on
  functions), checked with `jsdoc/no-restricted-syntax`. The field checks
  only match plain node types (`FunctionDeclaration`, `VariableDeclaration`,
  `ExportNamedDeclaration`); combinator selectors silently match nothing, so
  a negative test file was used to confirm each rule fires. The
  `doc-coverage` stage runs only these rules and a `jsdoc --pedantic` parse
  (JSDoc 4 rejects TypeScript-style types such as `import(...)` and exits 0
  on parse errors without `--pedantic`). `make test` also starts the runtime
  image and checks the page, the module, the headers, the hidden endpoints,
  the JSON log and the UID.

## Consequences

- `2 + 3` is clicked in a real browser (headless Chromium) and shows `5`
  1.2 s after `=`; P1.9 turns that check into `make e2e`.
- The component is named `shell` in the root Makefile (`make test-shell`) and
  `frontend-shell` in Compose and commit scopes, as for every microfrontend.
- `.prettierignore` gets the `conf` header type.
- P8.1–P8.15 replace the page; the state machine and the API client may be
  reused by the display and key microfrontends.
