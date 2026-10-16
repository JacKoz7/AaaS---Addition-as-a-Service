# Service Charter — `gateway`

| Field | Value |
| --- | --- |
| Document | Service Charter |
| Component | `gateway` |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Service Version | 0.1.0 |
| Last Reviewed | 2026-10-16 |
| Review Cadence | On every minor version of the service, and at least once per phase |

## 1. Mission

`gateway` is the single entry point of AaaS. Every request of the calculator
(the frontend, each key press, the task status poll and, from later phases,
the timer stream, the invoice download and the login) arrives on host port
80 and is routed by the gateway to exactly one owning service. Errors that
arise at the edge are returned as RFC 9457 problem details, like every other
error of the AaaS API.

## 2. Business Value

AaaS exists to add two non-negative integers with a level of rigour no native
`+` operator can offer. `gateway` contributes to that proposition by
guaranteeing **security and consistency at the boundary**: one published
port, one routing table derived from the public API contract
(`CLAUDE.md` 4.1), one error format, and (from P6.2) one place where every
request is authenticated and rate-limited before it can consume a single
successor call. Without it, each service would have to be exposed and
hardened separately, and the user would receive errors in as many formats
as there are languages in AaaS.

## 3. Stakeholders

| Stakeholder | Interest |
| --- | --- |
| Platform Enablement Guild (PEG) | Owns, builds and operates the service |
| End user of the calculator | Reaches the calculator and the API on one address and receives consistent errors |
| Customer Experience Tribe (CXT) | Owns `expression-assembler`, `stopwatch` and the frontend served behind the gateway |
| Transaction Integrity Office (TIO) | Owns the `ledger` (task status until P3.3) and the `saga-orchestrator` behind `/api/v1/tasks` |
| Trust & Identity Board (TIB) | Owns `auth` and `rate-limiter`, attached to the gateway in P6.1 and P6.2 |
| Observability Steering Group (OSG) | Consumes the gateway's metrics and access logs (P7.x) |

## 4. Scope

### In Scope

- Accepting HTTP on host port 80 (container port 8000) and routing by path
  to the owning service (`docs/API.md`, section 1).
- Answering unknown `/api` paths with a 404 problem.
- Rewriting every API error that is not already RFC 9457 into problem
  details (502, 503 and 504 raised by the gateway itself included).
- Connection and response-header timeouts (2 s) and up to three attempts
  when an upstream cannot be reached.
- `GET /health` and `GET /metrics` on the internal port 8080.
- Structured JSON logs and access logs on stdout.

### Out of Scope

- Any user-visible feature beyond the calculator keypad, display, timer and
  invoice download (`CLAUDE.md` section 1).
- Access to the database of any other service (`CLAUDE.md` section 1, rule 4).
- Business logic of any kind: the gateway never inspects or changes request
  bodies.
- Authentication and rate limiting: delegated to `rate-limiter` through
  forwardAuth from P6.2; the gateway only wires the middleware.
- Dynamic routes: the Redis route table and its provider arrive in P5.4.
- TLS termination: AaaS is bound to the loopback interface until public
  access (Phase 12, deferred).

## 5. Key Performance Indicators

| KPI | Definition | Target | Source |
| --- | --- | --- | --- |
| Availability | Share of successful `GET /health` probes | See SLO.md | Compose health check; Prometheus from P7.1 |
| Edge error share | Responses with status 502, 503 or 504 / all responses on API routers | < 0.1% while all upstreams are healthy | `traefik_router_requests_total{code=~"50[234]"}` |
| Gateway overhead | p99 of `traefik_entrypoint_request_duration_seconds` minus upstream time | < 10 ms | Traefik metrics, access log `Overhead` |

## 6. Related Documents

[RACI](RACI.md) · [SLO](SLO.md) · [Runbook](RUNBOOK.md) ·
[Threat Model](THREAT_MODEL.md) · [Data Classification](DATA_CLASSIFICATION.md) ·
[Dependencies](DEPENDENCIES.md) · [Capacity](CAPACITY.md) · [API](API.md) ·
[Changelog](CHANGELOG.md) · [README](../README.md) ·
[ADR-0012](../../../docs/adr/0012-gateway-traefik-file-routing.md)
