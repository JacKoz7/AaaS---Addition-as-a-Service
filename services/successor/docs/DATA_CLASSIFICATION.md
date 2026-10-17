# Data Classification — `successor`

| Field | Value |
| --- | --- |
| Document | Data Classification |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
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

Store: CouchDB (container), volume `successor-data`.

| Data Item | Location | Classification | Retention | Personal Data |
| --- | --- | --- | --- | --- |
| Database password | Environment (`SUCCESSOR_DB_PASSWORD`), OpenBao from P5.3 | CONFIDENTIAL | Until rotated | No |
| Call documents (`taskId`, `n`, `result`, `eventId`, `event`, `calledAt`, `traceId`) | CouchDB `successor_calls` | INTERNAL | Unlimited (no retention job, R-014) | No |
| Migration records | CouchDB `successor_migrations` | INTERNAL | Lifetime of the database | No |
| Published events (`n`, `result`, identifiers, traceparent) | Redpanda `aaas.successor.called.v1` | INTERNAL | Topic retention (ADR-0011) | No |
| Log fields `taskId`, `traceId`, `spanId`, `n`, results, dependency errors | stdout (container logs, Loki from P7.1) | INTERNAL | Docker log rotation; Loki retention from P7.1 | No |

The service never receives a session identifier.

## 3. Handling Rules

- Data is never read by another service directly (CLAUDE.md section 1,
  rule 4); other services obtain it through the contracts in API.md.
- CONFIDENTIAL values are never written to logs.
- Deleting the `successor-data` volume (`make clean`) erases all stored data.
