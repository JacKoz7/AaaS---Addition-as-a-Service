# Service Level Objectives — `parser`

| Field | Value |
| --- | --- |
| Document | Service Level Objectives |
| Component | `parser` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |
| Measurement Window | Rolling 30 days |

## 1. Service Level Indicators

| SLI | Definition | Measured From |
| --- | --- | --- |
| Availability | Successful `GET /health` probes / all probes | Compose healthcheck, Prometheus (from P7.1) |

| Correctness | Consumed events that end in exactly one outcome without a second request: `published + republished + duplicate + rejected` over all consumed events whose expression decoded | `parser_events_consumed_total{outcome}`; the contract test of the Dockerfile `test` stage for the content |
| Processing health | Processing attempts that did not fail: 1 − `parser_processing_failures_total` / consumed events | `parser_processing_failures_total`, `parser_events_consumed_total` |
| Latency | Time from `occurredAt` of `aaas.expression.submitted.v1` to `occurredAt` of the produced `aaas.addition.requested.v1`, p99 | Event timestamps (until a histogram arrives with P7.3) |

## 2. Objectives

| SLI | Objective | Error Budget (30 days) |
| --- | --- | --- |
| Availability | 99.9% | 43 minutes 12 seconds |

| Correctness | 99.999% | 26 seconds of wrong outcomes; in practice none is tolerated |
| Processing health | 99.9% | 1 failed attempt per 1 000 events |
| Latency | p99 below 500 ms | 0.1% of events slower |

Measured on 2026-10-17 (200 expressions through the gateway, 8 clients):
p50 13 ms, p95 79 ms, maximum 113 ms; 200 of 200 published, no duplicates.

## 3. Error Budget Policy

- Budget remaining: feature work and refactoring proceed normally.
- Budget exhausted: only reliability fixes are merged until the budget
  recovers; the owning team writes a postmortem
  (`docs/governance/INCIDENT_POSTMORTEM_TEMPLATE.md`).

## 4. Caveats

AaaS runs on a single workstation with Docker Compose. Objectives are
measured while the system is running (`make up`); time when the host is
switched off is excluded from the window.
