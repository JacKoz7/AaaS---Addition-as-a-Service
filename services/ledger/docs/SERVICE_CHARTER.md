# Service Charter — `ledger`

| Field | Value |
| --- | --- |
| Document | Service Charter |
| Component | `ledger` |
| Owning Team | Transaction Integrity Office (TIO) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Service Version | 0.1.0 |
| Last Reviewed | 2026-10-17 |
| Review Cadence | On every minor version of the service, and at least once per phase |

## 1. Mission

Immutable hash-chained record of every result.

The ledger is the system of record of AaaS: every completed addition becomes
exactly one entry of a hash chain in immudb, linked to the previous entry by
`sha256(prevHash|taskId|a|b|result|recordedAt)` (ADR-0013), and is announced
once as `aaas.ledger.appended.v1` (`CLAUDE.md` 3, step 10). Until the saga
exists (P3.3) the ledger also performs the addition itself, as `b` calls of
the successor service, and answers the task status for the display.

## 2. Business Value

AaaS exists to add two non-negative integers with a level of rigour no native
`+` operator can offer. `ledger` contributes to that proposition as
described below.

A result is only as valuable as the confidence that it was never changed.
The ledger provides that confidence: every entry is written once, never
updated, and protected by a chain in which altering any recorded addition
breaks every later link, in a database that itself keeps every version of
every row. It is also the moment a result becomes **official**: the
stopwatch stops (P8.16) and the 0.00 PLN invoice is issued (P9.1) only once
the ledger has announced the entry. In phase 1 the ledger additionally
carries the Peano computation, so that the first end-to-end addition of the
organisation (milestone M1) does not have to wait for the saga.

## 3. Stakeholders

| Stakeholder | Interest |
| --- | --- |
| Transaction Integrity Office (TIO) | Owns, builds and operates the service |
| End user of the calculator | Sees the progress and the result of the addition |
| Arithmetic Excellence Center (AEC) | Owns `parser` (producer of the consumed event) and `successor` (called `b` times per addition) |
| Customer Experience Tribe (CXT) | Display polls the task status; `stopwatch` consumes the announcement (P8.16) |
| Revenue Operations Unit (ROU) | `billing` consumes the announcement (P9.1) |
| Cloud Governance Committee (CGC) | `cloud-notary` verifies the chain from the announcement (P10.3) |
| Platform Enablement Guild (PEG) | Operates Redpanda and the gateway route of the task status |

## 4. Scope

### In Scope

- Append one entry per recorded addition to the hash chain, with no gaps
  and no forks, and announce it as `aaas.ledger.appended.v1` (at least once,
  keyed by `taskId`).
- Consume `aaas.addition.requested.v1` idempotently (`TEMPORARY(P3.4)`:
  `aaas.result.voted.v1` from P3.4).
- Count `a + b` as `b` successor calls, resumable from a checkpoint
  (`TEMPORARY(P3.3)`).
- Serve `GET /api/v1/tasks/{taskId}` (`TEMPORARY(P3.3)`), `GET /health` and
  `GET /metrics`.

### Out of Scope

- Any user-visible feature beyond the calculator keypad, display, timer and
  invoice download (CLAUDE.md section 1).
- Access to the database of any other service (CLAUDE.md section 1, rule 4).
- Computing `n + 1` (the successor) and validating operands (validator,
  P2.14).
- Verifying the whole chain on request (`GET /api/v1/ledger/verify`, P3.7)
  and sending entries to SQS (P10.4).
- Deciding the result from a vote (`consensus`, P4.5).

## 5. Key Performance Indicators

| KPI | Definition | Target | Source |
| --- | --- | --- | --- |
| Availability | Share of successful `GET /health` probes | 99.9% (SLO.md) | Compose health check, Prometheus |
| Recorded additions | Entries appended per day | Reported, not targeted | `ledger_entries_appended_total` |
| Chain integrity | Entries whose link or hash does not verify | 0, always | `GET /api/v1/ledger/verify` (P3.7); until then the check in RUNBOOK.md |
| Successor call rate | Successful successor calls per second | Reported; decides the waiting time of an addition | `ledger_successor_calls_total{outcome="ok"}` |
| Failed tasks | Tasks that ended `FAILED` | 0 in normal operation | `ledger_tasks_finished_total{status="FAILED"}` |

## 6. Related Documents

[RACI](RACI.md) · [SLO](SLO.md) · [Runbook](RUNBOOK.md) ·
[Threat Model](THREAT_MODEL.md) · [Data Classification](DATA_CLASSIFICATION.md) ·
[Dependencies](DEPENDENCIES.md) · [Capacity](CAPACITY.md) · [API](API.md) ·
[Changelog](CHANGELOG.md) · [README](../README.md) ·
[ADR-0017](../../../docs/adr/0017-ledger-nim-immudb-rest-and-librdkafka.md)
