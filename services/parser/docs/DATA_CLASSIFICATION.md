# Data Classification — `parser`

| Field | Value |
| --- | --- |
| Document | Data Classification |
| Component | `parser` |
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

Store: SQLite (embedded), volume `parser-data`.

| Data Item | Location | Classification | Retention | Personal Data |
| --- | --- | --- | --- | --- |
| Expression texts and their ASTs | `ast_cache` | INTERNAL | Unlimited (no retention job, R-012) | No |
| Consumed event identifiers, task identifiers, outcomes and rejection reasons | `processed_events` | INTERNAL | Unlimited (no retention job, R-012) | No |
| Produced events (operands, identifiers, traceparent) | `processed_events.output_event` | INTERNAL | Unlimited (no retention job, R-012) | No |
| Applied migrations | `schema_migrations` | INTERNAL | Lifetime of the database | No |
| Log fields `taskId`, `traceId`, `spanId`, operands, rejection reasons | stdout (container logs, Loki from P7.1) | INTERNAL | Docker log rotation; Loki retention from P7.1 | No |

The consumed event carries a `sessionId` (personal data, DPIA.md); the parser
neither stores nor logs it. SQLite needs no credentials, so the service holds
no CONFIDENTIAL data.

## 3. Handling Rules

- Data is never read by another service directly (CLAUDE.md section 1,
  rule 4); other services obtain it through the contracts in API.md.
- CONFIDENTIAL values are never written to logs.
- Deleting the `parser-data` volume (`make clean`) erases all stored data.
