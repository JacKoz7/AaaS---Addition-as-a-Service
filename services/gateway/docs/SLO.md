# Service Level Objectives — `gateway`

| Field | Value |
| --- | --- |
| Document | Service Level Objectives |
| Component | `gateway` |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-16 |
| Measurement Window | Rolling 30 days |

## 1. Service Level Indicators

| SLI | Definition | Measured From |
| --- | --- | --- |
| Availability | Successful `GET /health` probes / all probes | Compose health check, Prometheus (from P7.1) |
| Correct routing | Requests answered by the upstream that owns the path (CLAUDE.md 4.1), or by the 404 problem for unknown `/api` paths / all requests | Integration test `TestGateway` on every build; access log `RouterName` and `ServiceName` |
| Error format | API responses with status ≥ 400 and `Content-Type: application/problem+json` / API responses with status ≥ 400 | Integration and unit tests; access log |
| Gateway latency | p99 of the time the gateway adds to a request (access log `Overhead`, excluding retries) | Traefik access log; `traefik_entrypoint_request_duration_seconds` |

## 2. Objectives

| SLI | Objective | Error Budget (30 days) |
| --- | --- | --- |
| Availability | 99.9% | 43 minutes 12 seconds |
| Correct routing | 100% (a misrouted request could reach the wrong service) | None: any violation is an incident |
| Error format | 99.999% | 0.001% of API error responses |
| Gateway latency | p99 < 10 ms | 1% of requests above 10 ms |

## 3. Error Budget Policy

- Budget remaining: feature work and refactoring proceed normally.
- Budget exhausted: only reliability fixes are merged until the budget
  recovers; the owning team writes a postmortem
  (`docs/governance/INCIDENT_POSTMORTEM_TEMPLATE.md`).

## 4. Caveats

AaaS runs on a single workstation with Docker Compose. Objectives are
measured while the system is running (`make up`); time when the host is
switched off is excluded from the window. Errors caused by an unavailable
upstream (502, 503, 504) count against the upstream's SLO, not the
gateway's, as long as they are returned as problem details.
