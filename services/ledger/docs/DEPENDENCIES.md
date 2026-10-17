# Dependencies — `ledger`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `ledger` |
| Owning Team | Transaction Integrity Office (TIO) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Upstream (this service depends on)

| Dependency | Kind | Contract | Effect of Failure |
| --- | --- | --- | --- |
| immudb (`ledger-db`) | Database (container), REST API v1 | Private schema in `migrations/` | `/health` `database: failing`; events are not consumed (retried, offsets not committed); checkpoints are skipped; appends wait. Each request: 2 s deadline, 3 attempts with jitter |
| `ledger-db-init` | One-shot container | `immudb/provision.sh` | The ledger does not start until it exits 0 |
| Redpanda | Event bus | `aaas.addition.requested.v1` (in, group `ledger`), `aaas.ledger.appended.v1` (out) | `/health` `broker: failing`; no new tasks; publications retried until acknowledged (5 s message timeout per attempt) |
| `parser` (AEC) | Producer of `aaas.addition.requested.v1` | [schema](../../../contracts/events/aaas.addition.requested.v1.schema.json) | No new additions; nothing is lost |
| `successor` (AEC) | HTTP `POST /v1/next` (`TEMPORARY(P2.1)`: gRPC later) | services/successor/README.md | Counting pauses; each call retried (2 s deadline, backoff 100 ms doubling to 5 s, full jitter; `TEMPORARY(P3.6)`: without limit); a 4xx marks the task `FAILED` |
| Gateway (PEG) | Route `GET /api/v1/tasks/{taskId}` (upstream `tasks`) | services/gateway/config/dynamic/routes.yml | The display cannot see the status; counting continues |

## 2. Downstream (depends on this service)

| Dependant | Kind | Contract | Effect of Our Failure |
| --- | --- | --- | --- |
| Display (temporary frontend P1.8, `frontend/display` P8.2) | `GET /api/v1/tasks/{taskId}` through the gateway | API.md | Status unavailable (502 from the gateway); the addition resumes after a restart |
| `stopwatch` (CXT, P8.16) | Consumer of `aaas.ledger.appended.v1` | [schema](../../../contracts/events/aaas.ledger.appended.v1.schema.json) | The official time does not stop until the entry is announced |
| `billing` (ROU, P9.1) | Consumer of `aaas.ledger.appended.v1` | same | The invoice waits for the announcement |
| `cloud-notary` (CGC, P10.3) | Copy of the entry through SQS (P10.4) | same payload | The chain is verified later |

## 3. Build-Time Dependencies

| Dependency | Version | Licence |
| --- | --- | --- |
| `nimlang/nim` (toolchain image, Debian bookworm) | 2.2.12 | MIT |
| Nim standard library and `checksums` (shipped with Nim) | 2.2.12 | MIT |
| librdkafka (`librdkafka-dev`, `librdkafka1`) | 2.0.2-1 | BSD-2-Clause |
| `debian` (runtime image) | bookworm-20251020-slim | DFSG (various open-source) |
| wget (health check) | 1.21.3-1+deb12u1 | GPL-3.0-or-later |
| `codenotary/immudb` (database image) | 1.11.2 | Business Source License 1.1 (since 1.9DOM.2): free of charge, production use granted for anything that is not a competing paid offering; each release becomes Apache-2.0 four years after publication. Not an OSI licence; accepted under CLAUDE.md 1, rule 3 ("open source / free") in ADR-0017, R-016 |
| `curlimages/curl` (provisioning image) | 8.17.0 | curl licence (MIT-style) |
| Python test tools: jsonschema, referencing and dependencies | pinned in the Dockerfile | MIT, Apache-2.0 |
