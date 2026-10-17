# Service Level Objectives — `ledger`

| Field | Value |
| --- | --- |
| Document | Service Level Objectives |
| Component | `ledger` |
| Owning Team | Transaction Integrity Office (TIO) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |
| Measurement Window | Rolling 30 days |

## 1. Service Level Indicators

| SLI | Definition | Measured From |
| --- | --- | --- |
| Availability | Successful `GET /health` probes / all probes | Compose health check, Prometheus (from P7.1) |
| Correctness | Recorded entries whose result equals `a + b` and whose link and hash verify / all recorded entries | Chain check of RUNBOOK.md §3.2; `GET /api/v1/ledger/verify` from P3.7; consensus from P4.5 |
| Exactly one entry per task | Tasks with more than one entry | Unique index `ledger_entries(task_id)`; can only be 0 |
| Announcement | Entries without an acknowledged publication 1 minute after appending / all entries | `publications` table (RUNBOOK.md §3.1) |
| Counting throughput | Successful successor calls per second while a task is counting | `rate(ledger_successor_calls_total{outcome="ok"}[1m])` |

## 2. Objectives

| SLI | Objective | Error Budget (30 days) |
| --- | --- | --- |
| Availability | 99.9% | 43 minutes 12 seconds |
| Correctness | 100% | None: a single wrong entry is an incident |
| Exactly one entry per task | 100% | None (enforced by the database) |
| Announcement | 99.99% | 1 entry in 10 000 published late |
| Counting throughput | At least 200 calls/s for one task (measured 2.3 ms per call, CAPACITY.md) | Reported per release |

## 3. Error Budget Policy

- Budget remaining: feature work and refactoring proceed normally.
- Budget exhausted: only reliability fixes are merged until the budget
  recovers; the owning team writes a postmortem
  (`docs/governance/INCIDENT_POSTMORTEM_TEMPLATE.md`).

## 4. Caveats

AaaS runs on a single workstation with Docker Compose. Objectives are
measured while the system is running (`make up`); time when the host is
switched off is excluded from the window. The throughput objective depends
on the successor and its CouchDB (`successor`, CAPACITY.md), which serve
every call.
