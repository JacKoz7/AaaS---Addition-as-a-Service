# Service Level Objectives — `frontend-shell`

| Field | Value |
| --- | --- |
| Document | Service Level Objectives |
| Component | `frontend-shell` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |
| Measurement Window | Rolling 30 days |

## 1. Service Level Indicators

| SLI | Definition | Measured From |
| --- | --- | --- |
| Availability | Successful `GET /health` probes / all probes | Compose health check, Prometheus (from P7.1) |
| Correct display | Results shown equal to the `result` of the task view | Browser tests (P1.9 `make e2e`) |
| Page load | `GET /` through the gateway answered 200 / all | Gateway access log |

## 2. Objectives

| SLI | Objective | Error Budget (30 days) |
| --- | --- | --- |
| Availability | 99.9% | 43 minutes 12 seconds |
| Correct display | 100% | None: a wrong number on the display is an incident |
| Page load | 99.9% | 1 in 1 000 loads |

## 3. Error Budget Policy

- Budget remaining: feature work and refactoring proceed normally.
- Budget exhausted: only reliability fixes are merged until the budget
  recovers; the owning team writes a postmortem
  (`docs/governance/INCIDENT_POSTMORTEM_TEMPLATE.md`).

## 4. Caveats

AaaS runs on a single workstation with Docker Compose. Objectives are
measured while the system is running (`make up`). The time to a result
depends on the services behind the API, not on this page.
