<!-- GENERATED FILE: produced from the contracts in contracts/ by the
     steps that introduce each contract type (events P1.3, proto P2.1,
     OpenAPI P2.2; ADR-0010). Until then it is kept in sync by hand with the
     contracts; do not add content that is not in a contract. The native API
     documentation is published in the portal by `make docs`. -->
# API Reference — `ledger`

| Field | Value |
| --- | --- |
| Document | API Reference |
| Component | `ledger` |
| Owning Team | Transaction Integrity Office (TIO) |
| Classification | INTERNAL |
| Service Version | 0.1.0 |

## 1. HTTP (port 8080)

| Method | Path | Description | Response |
| --- | --- | --- | --- |
| `GET` | `/api/v1/tasks/{taskId}` | Status of an addition (public API `CLAUDE.md` 4.1, through the gateway; `TEMPORARY(P3.3)`: the saga-orchestrator answers it from P3.3) | `200 { "taskId", "status", "a", "b", "progress": { "done", "total" }, "result"? }`; `400` taskId not a lowercase UUID; `404` unknown task; `503` database unavailable |
| `GET` | `/health` | Liveness and readiness | `200 { "status": "ok", "checks": { "database": "ok", "broker": "ok" } }`, `503` with `"failing"` when a check fails |
| `GET` | `/metrics` | Prometheus metrics | `200 text/plain; version=0.0.4` |

Any other path is `404`, any other method `405`. Errors use RFC 9457
(`application/problem+json`, `type` `about:blank`).

`status` is `COUNTING` (successor calls in progress, `progress.done` of
`progress.total = b`), `RECORDING` (counted, entry being appended),
`RECORDED` (in the ledger; `result` present) or `FAILED` (the successor
refused a call). A task is `404` until the ledger has consumed its
`aaas.addition.requested.v1`.

Example: `GET /api/v1/tasks/01a14aa9-5613-7d39-a926-f4181f33b699` →
`{"taskId":"01a14aa9-5613-7d39-a926-f4181f33b699","status":"RECORDED","a":2,"b":3,"progress":{"done":3,"total":3},"result":5}`.

### Metrics

| Metric | Type | Labels | Meaning |
| --- | --- | --- | --- |
| `ledger_up` | gauge | | 1 while the process runs |
| `ledger_build_info` | gauge | `version` | Version of the running ledger |
| `ledger_events_consumed_total` | counter | `outcome`: `new_task`, `duplicate`, `known_task`, `rejected` | Consumed `aaas.addition.requested.v1` messages |
| `ledger_successor_calls_total` | counter | `outcome`: `ok`, `unavailable`, `timeout`, `error`, `rejected`, `invalid` | Attempts of successor calls |
| `ledger_successor_call_seconds_total` | counter | | Seconds spent in successful successor calls |
| `ledger_tasks_active` | gauge | | Tasks being counted or recorded |
| `ledger_tasks_finished_total` | counter | `status`: `RECORDED`, `FAILED` | Tasks that ended |
| `ledger_entries_appended_total` | counter | | Entries appended to the hash chain |
| `ledger_publish_failures_total` | counter | | Failed publications of `aaas.ledger.appended.v1` (each retried) |
| `ledger_database_failures_total` | counter | | Database operations that failed after their retries |

## 2. gRPC (port 9090)

None: the ledger has no gRPC interface (`CLAUDE.md` 4.3).

## 3. Events

Outgoing call: `POST /v1/next` of `successor` (`TEMPORARY(P3.3)`), see
services/successor/README.md. Until P3.4 the ledger consumes
`aaas.addition.requested.v1`; `aaas.result.voted.v1`, its consumed event
from P3.4 on, is listed below because the registry names the ledger as its
consumer.

<!-- BEGIN GENERATED: events (scripts/service-api.py, do not edit) -->
### `aaas.ledger.appended.v1` (produced)

A result appended to the hash-chained ledger.

- Producer: `ledger`; partitions: 3; message key: `taskId`.
- Schema: [`aaas.ledger.appended.v1.schema.json`](../../../contracts/events/aaas.ledger.appended.v1.schema.json) (`urn:aaas:events:aaas.ledger.appended.v1`), in the envelope of `CLAUDE.md` 4.2.

| Payload field | Required | Description |
| --- | --- | --- |
| `sequence` | yes | Position of the entry in the hash chain: 1 for the first entry, then increasing by one without gaps. |
| `a` | yes | First operand of the recorded addition. |
| `b` | yes | Second operand of the recorded addition. |
| `result` | yes | Recorded result of the addition. |
| `recordedAt` | yes | Instant the entry was appended; part of the hashed content, so it is fixed in the millisecond UTC form. |
| `prevHash` | yes | Hash of the previous entry; 64 zeros for the first entry (sequence 1). |
| `hash` | yes | SHA-256 of the UTF-8 string `prevHash\|taskId\|a\|b\|result\|recordedAt`: the fields joined by `\|`, numbers in decimal without leading zeros, taskId and recordedAt exactly as in the event (ADR-0013). |

### `aaas.addition.requested.v1` (consumed)

A parsed addition of a and b; from P2.17 validated, with b the smaller operand.

- Producer: `parser`; partitions: 3; message key: `taskId`.
- Schema: [`aaas.addition.requested.v1.schema.json`](../../../contracts/events/aaas.addition.requested.v1.schema.json) (`urn:aaas:events:aaas.addition.requested.v1`), in the envelope of `CLAUDE.md` 4.2.

| Payload field | Required | Description |
| --- | --- | --- |
| `a` | yes | First operand, the augend. |
| `b` | yes | Second operand, the addend: the number of successor calls. |

### `aaas.result.voted.v1` (consumed)

The sum computed by Peano and confirmed by the consensus vote.

- Producer: `outbox-relay`; partitions: 3; message key: `taskId`.
- Schema: [`aaas.result.voted.v1.schema.json`](../../../contracts/events/aaas.result.voted.v1.schema.json) (`urn:aaas:events:aaas.result.voted.v1`), in the envelope of `CLAUDE.md` 4.2.

| Payload field | Required | Description |
| --- | --- | --- |
| `a` | yes | First operand, as in aaas.addition.requested.v1. |
| `b` | yes | Second operand, as in aaas.addition.requested.v1. |
| `result` | yes | Sum computed by Peano arithmetic (b successor calls starting from a) and, from P4.5, equal to the result of the consensus majority. |

<!-- END GENERATED: events -->
