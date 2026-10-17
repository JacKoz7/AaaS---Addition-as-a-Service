<!-- GENERATED FILE: the events section is generated from contracts/events
     by `make api-md` (scripts/service-api.py) and checked by
     `make contracts-check`; the HTTP and gRPC sections are generated once
     their contracts exist (proto P2.1, OpenAPI P2.2) and are kept in sync by
     hand with CLAUDE.md 4.1 until then. Do not add content that is not in a
     contract. The native API documentation is published by `make docs`. -->
# API Reference — `gateway`

| Field | Value |
| --- | --- |
| Document | API Reference |
| Component | `gateway` |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Service Version | 0.1.0 |

## 1. HTTP — public entry point (host port 80, container port 8000)

Routes of the public API (`CLAUDE.md` 4.1) delivered so far; each later
step adds the route of the service it delivers. The gateway forwards method,
path, query, headers and body unchanged.

| Method | Path | Routed to | Since |
| --- | --- | --- | --- |
| any (`POST` by contract) | `/api/v1/keys` | `expression-assembler` | 0.1.0 |
| any (`GET` by contract) | `/api/v1/tasks/{taskId}` | `ledger` (`TEMPORARY(P3.3)`), then `saga-orchestrator` | 0.1.0 |
| any | `/api` and `/api/...` matching no route above | answered by the gateway: `404` problem | 0.1.0 |
| any | every other path (`/`, `/index.html`, ...) | `frontend-shell` | 0.1.0 |

Methods are enforced by the upstream services, not by the gateway.

### Errors

Every response with status ≥ 400 on an API route (`/api/...`) is RFC 9457
problem details (`Content-Type: application/problem+json`). A problem
document produced by the upstream passes through unchanged; any other error
response, including those raised by the gateway itself, is replaced by:

```json
{
  "type": "about:blank",
  "title": "Bad Gateway",
  "status": 502,
  "detail": "The upstream service is unavailable.",
  "instance": "/api/v1/keys"
}
```

| Status | Raised when | `detail` |
| --- | --- | --- |
| `404` | No API route matches the path | No route of the AaaS API matches the request path. |
| `502` | The upstream cannot be reached after 3 attempts | The upstream service is unavailable. |
| `503` | No healthy upstream server is available | No healthy upstream server is available. |
| `504` | No response headers from the upstream within 2 s | The upstream service did not respond in time. |
| other | A non-compliant upstream error | omitted |

Requests whose path contains an encoded reserved character (`%2F`, `%5C`,
`%00`, `%3B`, `%25`, `%3F`, `%23`) are rejected by the entry point with an
empty `400` response before routing. Errors on frontend paths are not rewritten.

## 2. HTTP — internal entry point (container port 8080, not published)

| Method | Path | Description | Response |
| --- | --- | --- | --- |
| `GET` | `/health` | Liveness and readiness | `200 {"status":"ok","checks":{"proxy":"ok"}}` |
| `GET` | `/metrics` | Prometheus metrics of Traefik (per entry point, router and service) | `200 text/plain; version=0.0.4` |

## 3. gRPC (port 9090)

None. The gateway has no gRPC interface.

## 4. Events

<!-- BEGIN GENERATED: events (scripts/service-api.py, do not edit) -->
`gateway` neither produces nor consumes events.

<!-- END GENERATED: events -->
