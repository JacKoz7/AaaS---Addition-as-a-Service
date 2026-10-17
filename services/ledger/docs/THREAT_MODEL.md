# Threat Model — `ledger`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `ledger` |
| Owning Team | Transaction Integrity Office (TIO) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Network: `services` (gateway, successor, Redpanda) and `data` (its own
  database only). No port is published on the host (CLAUDE.md 6.2).
- Data store: immudb (`ledger-db`), reachable only by this service and the
  one-shot `ledger-db-init`.
- Trust boundaries crossed:
  - **in**: `GET /api/v1/tasks/{taskId}` from the gateway (public API,
    unauthenticated until P6.2); `aaas.addition.requested.v1` from Redpanda
    (produced by `parser`);
  - **out**: `POST /v1/next` to `successor`; `aaas.ledger.appended.v1` to
    Redpanda; SQL over HTTP to immudb.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on the `services` network publishes a forged `aaas.addition.requested.v1` | Network segmentation; the event is checked field by field before it becomes a task; schema registry validation of producers (P3.1); Redpanda ACLs are not configured | Medium: any container on the bus can request an addition |
| Spoofing | A caller asks for another user's task status | Task identifiers are UUIDv7 with 74 random bits; the answer holds only operands and progress (no user data) | Low |
| Tampering | A recorded result is changed in the database | Insert-only entries; immudb keeps every version of every row; the hash chain breaks at the changed entry (RUNBOOK.md §3.2, `GET /api/v1/ledger/verify` in P3.7, cloud-notary in P10.3) | Low |
| Tampering | A wrong sum is recorded because the successor misbehaves | The sum comes only from successor calls; consensus votes on it from P4.5 | Medium until P4.5 |
| Tampering | Two entries for one task, or two entries at one position | Unique index on `task_id`, primary key on `entry_seq`, one append at a time (in-process lock, `TEMPORARY(P3.5)`: etcd from P3.5) | Low |
| Repudiation | An entry cannot be traced to its addition | Each entry carries its task and its event; logs with `taskId` and `traceId`; the trace of the event is continued | Low |
| Information Disclosure | Database credentials leak | Credentials from env (OpenBao in P5.3); the service holds only the read-write user of its database, never the superadmin (used once by `ledger-db-init`); `.env` git-ignored; immudb runs without dev mode, so every request needs a session | Low |
| Information Disclosure | immudb web console reachable | Port 8080 of `ledger-db` is only on the `data` network; nothing is published on the host | Low |
| Denial of Service | Many large additions exhaust memory or the successor | 64 MB limit (measured 3.7 MiB with three concurrent tasks); one connection per task; rate limits at the gateway (P6.2); queue of large additions in Phase 12 | Medium: the number of concurrent tasks is not limited yet |
| Denial of Service | Broker or database down | Events wait in Redpanda; writes are retried; tasks resume from checkpoints | Low |
| Elevation of Privilege | A compromised process gains host access | Non-root user (UID 10001), Debian slim runtime with two packages | Low |

No High risk; the medium risks are covered by later steps (P3.1, P4.5,
P6.2) and recorded in `docs/governance/RISK_REGISTER.md` where they are
cross-service (R-015 for data growth).
