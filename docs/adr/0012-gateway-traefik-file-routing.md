# ADR-0012: Gateway — Traefik with file routes and a local RFC 9457 plugin

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-16 |
| Deciders | Platform Enablement Guild (PEG) |
| Step | P1.2 |

## Context

`CLAUDE.md` makes `gateway` (Traefik) the only entry point on host port 80,
with routes for the public API of section 4.1 and the frontend. Step P1.2
asks for file-based configuration; the Redis provider follows in P5.4 and
forwardAuth to `rate-limiter` in P6.2. Three further requirements apply to
every service and are not met by Traefik out of the box:

- `CLAUDE.md` 4.1: API errors are always RFC 9457 problem details. Traefik
  answers an unmatched path with plain-text `404 page not found`, an
  unreachable upstream with plain-text `502 Bad Gateway`, a timeout with
  `504 Gateway Timeout`.
- `CLAUDE.md` 6.1: `GET /health` with a JSON `{status, checks}` body and
  `GET /metrics` on port 8080. Traefik's ping endpoint answers plain `OK`.
- `CLAUDE.md` 6.1 and 6.2: no hard-coded hosts, timeouts (2 s) and retries
  (3 attempts) on every network call, a non-root user, graceful shutdown
  within 10 s, unit tests and 100% documentation coverage.

At the time of this step no upstream service exists yet.

## Decision

- **Image** `traefik:v3.7.14` (MIT, multi-arch) as the runtime stage of
  `services/gateway/Dockerfile`, running as UID 10001. The static and dynamic
  configuration and the plugin are copied into the image; nothing is
  mounted, so the tested image is the deployed one. The `infra/traefik/`
  directory of the repository layout is not used: the configuration is the
  service's code and lives in `services/gateway/config/`.
- **Entry points**: `web` on container port 8000 (unprivileged, because of
  the non-root user), published as `127.0.0.1:80` (loopback until public
  access in Phase 12); `internal` on 8080 for `/health` and Prometheus
  `/metrics`, not published. Both delete aliased header names and reject
  encoded reserved characters in paths (empty `400`). Shutdown: stop
  accepting at once, 8 s grace for requests in flight.
- **File provider** reading `/etc/traefik/dynamic/routes.yml` without
  watching. The file is a Go template: upstream URLs come from
  `AAAS_UPSTREAM_EXPRESSION_ASSEMBLER`, `AAAS_UPSTREAM_TASKS` and
  `AAAS_UPSTREAM_FRONTEND`, with the Compose service names as defaults
  (`CLAUDE.md` 6.1, no hard-coded hosts). The integration tests use the same
  variables to point the routes at stub servers.
- **Routes** in this step: `/api/v1/keys` → `expression-assembler`;
  `/api/v1/tasks/{taskId}` → `ledger` (`TEMPORARY(P3.3)`, the decision of
  step P1.7) and later `saga-orchestrator`; `/api` and `/api/...` without a
  route → 404 problem; everything else → `frontend-shell`. Explicit
  priorities (100, 20, 10) keep the order independent of rule length. The
  routes of `stopwatch`, `billing`, the ledger verification and `auth` are
  added by the steps that deliver those services, so the routing table only
  names services that are planned for the current phase.
- **Upstream policy**: one `serversTransport` with 2 s dial and 2 s
  response-header timeouts (streamed bodies are not limited, for SSE), and
  a `retry` middleware with 3 attempts and exponential backoff from 100 ms.
  Traefik retries only when no response has started, so a request that
  reached the upstream is not repeated.
- **Local plugin `edge`** (`services/gateway/src/edge`, Go standard library
  only, loaded from `/plugins-local` and interpreted by Traefik's Yaegi):
  one middleware with three modes. `problem` wraps the API routes and
  replaces any response ≥ 400 that is not `application/problem+json` by a
  problem document with the same status (upstream problem documents and
  successful or streamed responses pass through; `Flush` is forwarded).
  `not-found` answers the catch-all API router with a 404 problem. `health`
  answers `/health` with `{"status":"ok","checks":{"proxy":"ok"}}`. A local
  plugin was preferred to an extra error-page container because it adds no
  hop and no process, and to a plugin from the Traefik catalog because it is
  never downloaded at runtime.
- **Tests** in `services/gateway/tests` (own Go module): unit tests of the
  plugin through `CreateConfig` and `New`, and an integration test that runs
  the real Traefik binary (copied from the runtime image) with the real
  configuration and plugin against stub upstreams, covering routing, header
  forwarding, error rewriting, the 504 timeout, the 502 for an unreachable
  upstream, health and metrics.
- **Documentation coverage** for Go (`CLAUDE.md` 6.5.4: revive `exported`
  plus a check of unexported symbols): revive v1.17.1 with `exported` and
  `package-comments`, and godoclint v0.11.4 with `require-doc` for exported
  and unexported symbols including tests. godoclint pins
  `golang.org/x/tools` v0.49.0, which cannot read Go 1.27 export data, so it
  is built in the toolchain stage against x/tools v0.52.0. API
  documentation: doc2go v0.12.2 (static pkgsite-style HTML of the exported
  API) plus the configuration files, under an `index.html`.
- **No database yet.** `scripts/new-service.sh` scaffolds the catalog
  database (Redis) for every service; its container block, volume and
  password placeholder were removed, and P5.4 adds them back with the Redis
  provider.

## Consequences

- `make up` publishes the gateway on <http://127.0.0.1/>. Until the
  services of P1.4, P1.7 and P1.8 exist, their routes answer 502 (problem
  details on API routes, Traefik's plain text on the frontend route).
- Every API error the user can receive is RFC 9457, except the empty `400`
  for encoded reserved characters, which Traefik raises before routing and
  no AaaS client produces.
- Access logs and Traefik logs are JSON, but with Traefik's field names
  (`time`, `level`, `msg`, `RouterName`, ...) instead of the AaaS fields of
  `CLAUDE.md` 6.1; the OpenTelemetry Collector maps them in P7.1, and
  Traefik's native OTLP tracing is enabled in P7.2.
- Changing a route or timeout means editing `config/`, rebuilding and
  running the integration tests; the Redis provider of P5.4 moves the route
  table to runtime data.
- Future Go services (saga-orchestrator, consensus) reuse the documentation
  coverage setup (revive + godoclint built against a current x/tools).
