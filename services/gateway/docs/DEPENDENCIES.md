# Dependencies — `gateway`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `gateway` |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-16 |

## 1. Upstream (this service depends on)

The gateway starts without any upstream (no `depends_on`): a missing
upstream affects only its route. Every upstream call has a 2 s connection
timeout, a 2 s response-header timeout and up to 3 attempts with
exponential backoff from 100 ms when the connection fails (`CLAUDE.md` 6.1).
The gateway consumes no events, so there is no DLQ path.

| Dependency | Kind | Contract | Effect of Failure |
| --- | --- | --- | --- |
| `expression-assembler` (P1.4) | HTTP, `AAAS_UPSTREAM_EXPRESSION_ASSEMBLER` | `POST /api/v1/keys` (`CLAUDE.md` 4.1) | Key presses and `=` fail with 502/504 problems; no addition can start |
| `ledger` (P1.7, `TEMPORARY(P3.3)`), then `saga-orchestrator` (P3.3) | HTTP, `AAAS_UPSTREAM_TASKS` | `GET /api/v1/tasks/{taskId}` | The display cannot poll task status; additions in progress continue |
| `frontend-shell` (P1.8) | HTTP, `AAAS_UPSTREAM_FRONTEND` | `GET /*` (static files) | The calculator page does not load (plain 502, not an API route) |

From P5.4 the gateway also depends on its Redis route table, and from P6.2
on `rate-limiter` (forwardAuth); both are added to this table by those steps.

## 2. Downstream (depends on this service)

| Dependant | Kind | Contract | Effect of Our Failure |
| --- | --- | --- | --- |
| Browser (calculator user) | HTTP on host port 80 | `CLAUDE.md` 4.1 | AaaS is unreachable; no addition can be submitted or observed |
| Microfrontends (P1.8, Phase 8) | HTTP from the browser | `/api/v1/*` | As above |
| End-to-end tests (`tests/e2e`, P1.9) | HTTP | `CLAUDE.md` 4.1 | `make e2e` fails |
| Prometheus (P7.1) | HTTP scrape, port 8080 | `/metrics` | Gateway metrics missing |

## 3. Build-Time Dependencies

| Dependency | Version | Licence |
| --- | --- | --- |
| `traefik` image (runtime and test binary) | v3.7.14 | MIT |
| `golang` image (toolchain stages) | 1.27.2-alpine3.24 | BSD-3-Clause |
| revive | v1.17.1 | MIT |
| godoclint (`github.com/godoc-lint/godoc-lint`) | v0.11.4, built with `golang.org/x/tools` v0.52.0 | MIT (x/tools: BSD-3-Clause) |
| doc2go (`go.abhg.dev/doc2go`) | v0.12.2 | Apache-2.0 |

The `edge` plugin and the tests use the Go standard library only.
