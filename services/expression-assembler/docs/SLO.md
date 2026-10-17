# Service Level Objectives — `expression-assembler`

| Field | Value |
| --- | --- |
| Document | Service Level Objectives |
| Component | `expression-assembler` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |
| Measurement Window | Rolling 30 days |

## 1. Service Level Indicators

| SLI | Definition | Measured From |
| --- | --- | --- |
| Availability | Successful `GET /health` probes / all probes | Compose health check; Prometheus from P7.1 |
| Correct answers | `POST /api/v1/keys` answered with 202, 204 or a 4xx caused by the request / all key requests | `http_requests_received_total`, `expression_assembler_rejected_total` |
| Latency | p99 of `http_request_duration_seconds{endpoint="/api/v1/keys"}` | prometheus-net HTTP metrics |
| Exactly one task | Tasks per accepted `Idempotency-Key` | Unit, endpoint and storage tests on every build (`ConcurrentRetriesCreateOneTask`, `TasksAreUniquePerIdempotencyKey`) |

## 2. Objectives

| SLI | Objective | Error Budget (30 days) |
| --- | --- | --- |
| Availability | 99.9% | 43 minutes 12 seconds |
| Correct answers | 99.9% | 0.1% of key requests answered 503 |
| Latency | p99 < 100 ms (measured: 11 ms per key, 19 ms for `=`, see CAPACITY.md) | 1% of requests above 100 ms |
| Exactly one task | 100% | None: a second task for one key is an incident |

## 3. Error Budget Policy

- Budget remaining: feature work and refactoring proceed normally.
- Budget exhausted: only reliability fixes are merged until the budget
  recovers; the owning team writes a postmortem
  (`docs/governance/INCIDENT_POSTMORTEM_TEMPLATE.md`).

## 4. Caveats

AaaS runs on a single workstation with Docker Compose; time when the host is
switched off is excluded. A 503 caused by Redpanda or by the database counts
against this service's budget, because both are dependencies it cannot work
without. Every request has a 1.8 s budget (below the gateway's 2 s timeout),
so a slow dependency appears here as a 503, not as a gateway 504.
