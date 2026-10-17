# Dependencies — `parser`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `parser` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Upstream (this service depends on)

| Dependency | Kind | Contract | Effect of Failure |
| --- | --- | --- | --- |
| SQLite | Database (embedded) | Private schema in `migrations/` | `database` check fails; processing is retried in place (0.2 s backoff with jitter, three attempts, then every 5 s) |
| Redpanda | Event bus | Kafka protocol, `redpanda:9092` | At startup: waits up to 60 s for the topic metadata, then exits 1. Later: `broker` check fails; a publication times out after 2 s (2.5 s guard) and is retried as above without advancing the offset |
| `aaas.expression.submitted.v1` (producer: `expression-assembler`) | Consumed topic | [schema](../../../contracts/events/aaas.expression.submitted.v1.schema.json) | No new expressions; nothing is lost, consumption resumes at the committed offset |

## 2. Downstream (depends on this service)

| Dependant | Kind | Contract | Effect of Our Failure |
| --- | --- | --- | --- |
| `ledger` (P1.7, until P3.4) | Consumer of `aaas.addition.requested.v1` | [schema](../../../contracts/events/aaas.addition.requested.v1.schema.json) | Additions are not computed; tasks wait in `ACCEPTED` |
| `saga-orchestrator` (from P3.3) | Consumer of `aaas.addition.requested.v1` | [schema](../../../contracts/events/aaas.addition.requested.v1.schema.json) | No workflow starts; tasks wait in `ACCEPTED` |
| Compose healthcheck | `GET /health` | API.md | The container is reported unhealthy |

## 3. Build-Time Dependencies

| Dependency | Version | Licence |
| --- | --- | --- |
| `ocaml/opam` (build image) | `alpine-3.22-ocaml-4.14` | MIT (image), LGPL-2.1 with linking exception (OCaml) |
| `alpine` (runtime image) | 3.22.2 | MIT (base), per-package licences |
| OCaml | 4.14.2 | LGPL-2.1 with OCaml linking exception |
| dune | 3.20.2 | MIT |
| kafka, kafka_lwt (librdkafka bindings) | 0.5 | MIT |
| librdkafka (Alpine package) | 2.10.0-r0 | BSD-2-Clause |
| lwt | 5.9.2 | MIT |
| cohttp-lwt-unix | 6.1.1 | ISC |
| sqlite3 (bindings) | 5.3.1 | MIT |
| SQLite (Alpine package `sqlite-libs`) | 3.49.2-r1 | Public domain |
| yojson | 3.0.0 | BSD-3-Clause |
| alcotest, alcotest-lwt (tests) | 1.9.1 | ISC |
| ocamlformat (lint) | 0.28.1 | MIT |
| odoc (documentation) | 3.1.0 | ISC |
| Python 3, py3-jsonschema, py3-referencing (contract test) | 3.12.15-r0, 4.23.0-r0, 0.36.2-r1 | PSF-2.0, MIT, MIT |
