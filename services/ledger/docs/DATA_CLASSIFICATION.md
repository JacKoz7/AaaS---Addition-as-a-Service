# Data Classification — `ledger`

| Field | Value |
| --- | --- |
| Document | Data Classification |
| Component | `ledger` |
| Owning Team | Transaction Integrity Office (TIO) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Classification Levels

| Level | Meaning |
| --- | --- |
| PUBLIC | May be shown to anyone (for example the result of 2 + 3) |
| INTERNAL | Operational data of AaaS; not shown to users |
| CONFIDENTIAL | Credentials, tokens and identifiers linkable to a person |

## 2. Data Inventory

Store: immudb (container `ledger-db`), volume `ledger-data`. immudb keeps
every version of every row; nothing is deleted.

| Data Item | Location | Classification | Retention | Personal Data |
| --- | --- | --- | --- | --- |
| Operands, result, status and progress of a task | `tasks`, `/api/v1/tasks/{taskId}` | PUBLIC | Lifetime of the volume | No |
| Task identifier | `tasks`, `processed_events`, `ledger_entries`, logs | INTERNAL | Lifetime of the volume; logs per Docker log rotation | No (not linked to a session in this service) |
| Ledger entries (sequence, operands, result, timestamps, hashes) | `ledger_entries` | INTERNAL | Lifetime of the volume (the record of results) | No |
| Published events | `ledger_entries.event`, Redpanda topic | INTERNAL | Volume; topic retention of Redpanda | No |
| Consumed event identifiers | `processed_events` | INTERNAL | Lifetime of the volume | No |
| Trace context | `tasks.traceparent`, logs | INTERNAL | Lifetime of the volume | No |
| Failure reason | `tasks.failure`, logs | INTERNAL | Lifetime of the volume | No |
| immudb session token | Process memory only | CONFIDENTIAL | 24 h, renewed on expiry | No |
| Database password | Environment (`LEDGER_DB_PASSWORD`), OpenBao from P5.3 | CONFIDENTIAL | Until rotated | No |
| immudb superadmin password | Environment of `ledger-db` and `ledger-db-init` only (`LEDGER_DB_ADMIN_PASSWORD`) | CONFIDENTIAL | Until rotated | No |

The ledger never receives the session identifier of the calculator
(`expression-assembler` keeps it); no personal data is processed
(docs/governance/DPIA.md).

## 3. Handling Rules

- Data is never read by another service directly (CLAUDE.md section 1,
  rule 4); other services obtain it through the contracts in API.md.
- CONFIDENTIAL values are never written to logs (passwords and tokens are
  not logged; immudb errors are logged by message only).
- Deleting the `ledger-data` volume (`make clean`) erases all stored data
  and restarts the chain at entry 1.
