# gateway

| Field | Value |
| --- | --- |
| Owning team | Platform Enablement Guild (PEG) |
| Language | Traefik v3.7 (configuration) + Go (local plugin `edge`) |
| Database | None until P5.4 (Redis route table) |
| Compose profile | `services` |
| Networks | `public`, `services` |
| Ports (container) | 8000 public entry point (host `127.0.0.1:80`), 8080 health and metrics |
| Version | 0.1.0 |

## Role

The only entry point of AaaS (`CLAUDE.md` 4.1). The browser loads the
calculator and calls the API on port 80; the gateway routes each path to the
service that owns it and turns every API error into RFC 9457 problem
details. It is the first hop of every addition (`CLAUDE.md` section 3): if
it is down, no key press reaches `expression-assembler` and no result can be
observed, although additions already accepted continue inside the system.

The routes come from files baked into the image (`config/`); the Redis
provider replaces them in P5.4, and the forwardAuth middleware to
`rate-limiter` is added in P6.2. See ADR-0012.

## Layout

| Path | Content |
| --- | --- |
| `config/traefik.yml` | Static configuration: entry points, file provider, local plugin, metrics, JSON logs, shutdown grace period |
| `config/dynamic/routes.yml` | Routes, middlewares, upstream services and timeouts (Go template: upstream URLs from `AAAS_UPSTREAM_*`) |
| `src/edge/` | Traefik middleware plugin (Go, standard library only): RFC 9457 errors, 404 for unknown API paths, JSON health |
| `tests/` | Unit tests of the plugin and integration tests that run Traefik with the real configuration |
| `revive.toml`, `.godoc-lint.yaml` | Documentation coverage rules (`CLAUDE.md` 6.5.4) |
| `api-docs.html` | Index page of the native API documentation |

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `POST /api/v1/keys` | in → `expression-assembler` | `CLAUDE.md` 4.1 |
| HTTP | `GET /api/v1/tasks/{taskId}` | in → `ledger` (`TEMPORARY(P3.3)`), then `saga-orchestrator` | `CLAUDE.md` 4.1 |
| HTTP | `/api/...` without a route | in, answered by the gateway | `404` problem |
| HTTP | `GET /*` | in → `frontend-shell` | static files |
| HTTP | `GET /health` (port 8080) | in | `{ "status": "ok", "checks": { "proxy": "ok" } }` |
| HTTP | `GET /metrics` (port 8080) | in | Prometheus text format |

Details, including the error table: [`docs/API.md`](docs/API.md).

## Database

None. The gateway is stateless until the Redis route table of P5.4.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `gateway` | Service name (image metadata; Traefik logs carry their own fields) |
| `AAAS_ENV` | `local` | Environment name; read from P5.2 |
| `AAAS_BOOTSTRAP` | `env` | `env` (read env vars) or `platform` (from P5.2) |
| `AAAS_HTTP_PORT` | `8080` | Port of the internal entry point (informational; fixed in `config/traefik.yml`) |
| `AAAS_UPSTREAM_EXPRESSION_ASSEMBLER` | `http://expression-assembler:8080` | Upstream of `/api/v1/keys` |
| `AAAS_UPSTREAM_TASKS` | `http://ledger:8080` | Upstream of `/api/v1/tasks/{taskId}` (`TEMPORARY(P3.3)`) |
| `AAAS_UPSTREAM_FRONTEND` | `http://frontend-shell:8080` | Upstream of every non-API path |

The upstream variables are read once at startup, when Traefik renders
`config/dynamic/routes.yml`.

## Running and testing

```sh
make build-gateway         # image through Compose (root Makefile)
make test-gateway          # unit + integration tests (Dockerfile `test` stage)
make lint-gateway          # gofmt check and go vet
make fmt-gateway           # gofmt -w
make doc-coverage-gateway  # revive `exported` + godoclint `require-doc` (100%)
make api-docs-gateway      # doc2go reference + configuration to build/api-docs/gateway
make up && curl -i http://127.0.0.1/api/v1/tasks/example
make logs SVC=gateway
```

From this directory: `make help`; `make run` starts the image alone on
`127.0.0.1:8000` and `127.0.0.1:8080`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
