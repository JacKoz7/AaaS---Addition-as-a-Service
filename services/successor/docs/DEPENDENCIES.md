# Dependencies — `successor`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Upstream (this service depends on)

| Dependency | Kind | Contract | Effect of Failure |
| --- | --- | --- | --- |
| CouchDB (`successor-db`) | Database (container) | Private schema in `migrations/` | At startup: migrations retried for 60 s, then exit 1. Later: `database` check fails; calls answer 503 after three attempts of 250 ms; the caller retries |
| Redpanda | Event bus | Kafka protocol, `redpanda:9092`; produces [`aaas.successor.called.v1`](../../../contracts/events/aaas.successor.called.v1.schema.json) | `broker` check fails; calls answer 503 after the 1 s message timeout; the caller retries |

## 2. Downstream (depends on this service)

| Dependant | Kind | Contract | Effect of Our Failure |
| --- | --- | --- | --- |
| `ledger` (P1.7, until P3.3) | Caller of `POST /v1/next` | API.md | Additions stop counting; they continue when the service is back |
| `saga-orchestrator` (from P3.3) | Caller of `Next` (gRPC from P2.1) | API.md, `contracts/proto/aaas/successor/v1/` (P2.1) | Activity retries; the workflow waits |
| Audit (no consumer yet) | `aaas.successor.called.v1` | [schema](../../../contracts/events/aaas.successor.called.v1.schema.json) | None |
| Compose healthcheck | `GET /health` | API.md | The container is reported unhealthy |

## 3. Build-Time Dependencies

| Dependency | Version | Licence |
| --- | --- | --- |
| `haskell` (build image) | `9.10.3-slim-bookworm` (GHC 9.10.3, cabal 3.14) | BSD-3-Clause (GHC), MIT (image) |
| `debian` (runtime image) | `bookworm-20251020-slim` | per-package licences (DFSG) |
| `couchdb` (database image base) | 3.5.1 | Apache-2.0 |
| librdkafka (`librdkafka-dev`, `librdkafka1`) | 2.0.2-1 | BSD-2-Clause |
| aeson | 2.3.2.0 | BSD-3-Clause |
| warp, wai | 3.4.16, 3.2.5 | MIT |
| wai-extra (tests) | 3.1.18 | MIT |
| http-client, http-types | 0.7.19, 0.12.6 | MIT, BSD-3-Clause |
| hw-kafka-client | 5.3.0 | MIT |
| prometheus-client | 1.1.2 | Apache-2.0 |
| text, bytestring, time, unix | 2.1.3, 0.12.2.0, 1.12.2, 2.8.7.0 | BSD-2-Clause / BSD-3-Clause |
| random, scientific | 1.2.1.3, 0.3.9.0 | BSD-3-Clause |
| hspec (tests) | 2.11.18 | MIT |
| ormolu (lint) | 0.8.0.2 | BSD-3-Clause |
| hlint (lint) | 3.10 | BSD-3-Clause |
| doctest (tests) | 0.25.0.2 | MIT |
| jsonschema and its tree (contract test) | 4.26.0 (versions of the documentation image) | MIT |

Every Haskell dependency is pinned by `cabal.project.freeze` (190
packages) at the `index-state` of `cabal.project`.
