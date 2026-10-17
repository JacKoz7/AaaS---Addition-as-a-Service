# parser

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | OCaml 4.14 (ADR-0015) |
| Database | SQLite (embedded, volume `parser-data`) |
| Compose profile | `services` |
| Networks | `services` |
| Ports (container) | 8080 HTTP (no gRPC) |
| Version | 0.1.0 |

## Role

Turns the text expression into an AST.

Step 4 of the request flow (`CLAUDE.md` 3): the parser consumes
`aaas.expression.submitted.v1`, parses `payload.expression` with the grammar
`number "+" number` and publishes `aaas.addition.requested.v1 { a, b }` with
the same `taskId`, continuing the trace. Each consumed event is processed
once (by `eventId`); an expression that is not an addition is rejected with
a reason and nothing is published. Until P2.17 the parser also refuses
operands above 99 999, which the produced event cannot carry; from P2.17 it
calls `validator`, `commutator` and `operator-registry`.

If the parser is down, submitted expressions wait in Redpanda and are
processed when it is back; tasks stay in `ACCEPTED` meanwhile.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| Event | `aaas.expression.submitted.v1` | in (group `parser`) | [schema](../../contracts/events/aaas.expression.submitted.v1.schema.json) |
| Event | `aaas.addition.requested.v1` | out (key `taskId`) | [schema](../../contracts/events/aaas.addition.requested.v1.schema.json) |
| HTTP | `GET /health` | in | `{ "status": "ok", "checks": { "database", "broker", "consumer" } }`, 503 on a failed check |
| HTTP | `GET /metrics` | in | Prometheus text format, metrics prefixed `parser_` |

Details: [docs/API.md](docs/API.md).

## Processing

1. Decode the event (tolerant reader); a message that is not an
   `aaas.expression.submitted.v1` event is discarded and logged.
2. Look up `eventId` in `processed_events`: `published` or `rejected` →
   duplicate, nothing happens; `pending` → publish the stored event again.
3. Parse through the AST cache. Rejection codes: `empty_expression`,
   `invalid_character`, `missing_operator`, `missing_left_operand`,
   `missing_right_operand`, `unexpected_operator`, and (until P2.17)
   `operand_out_of_range`.
4. Store the output event as `pending`, publish it, mark it `published`;
   then the consumer offset is stored.

Database and broker failures are retried in place (three quick attempts
with jitter, then every 5 s) without advancing the offset; P3.6 replaces
this with the dead-letter queue.

## Database

SQLite (embedded) at `/data/parser.db`, WAL mode, `synchronous = FULL`. The
service never reads another service's database. Migrations in
`migrations/` run at startup in order, each in a transaction, recorded in
`schema_migrations`.

| Table | Content |
| --- | --- |
| `ast_cache` | Expression text → AST (JSON), creation time, hit count |
| `processed_events` | Consumed `eventId` → task, status (`pending`, `published`, `rejected`), rejection reason, produced event, timestamps |
| `schema_migrations` | Applied migration files |

There is no retention job yet (R-012).

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `parser` | Service name used in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` until P5.2; `platform` is refused |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_KAFKA_BROKERS` | `redpanda:9092` | Kafka bootstrap servers |
| `AAAS_CONSUMER_GROUP` | `parser` | Consumer group of the committed offsets |
| `AAAS_DB_PATH` | `/data/parser.db` | SQLite file |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` or `fatal` |
| `AAAS_KAFKA_LOG_LEVEL` | `0` | librdkafka's own plain-text log level (0–7, 0 = silent; for debugging only) |

The service has no database password: SQLite has no credentials.

## Running and testing

```sh
make build-parser   # image through Compose (root Makefile)
make test-parser    # unit tests and the contract test in the `test` stage
make lint-parser    # ocamlformat check and warnings-as-errors build
make fmt-parser     # format sources in place
make doc-coverage-parser  # odoc build with warnings as errors
make api-docs-parser      # odoc HTML to build/api-docs/parser
make logs SVC=parser
```

The `test` stage runs 60 Alcotest cases (grammar, events, the SQLite store,
the processor with a fake publisher, configuration, health and metrics) and
validates every event the tests published against the JSON Schema of
`aaas.addition.requested.v1` (`scripts/validate-events.py --events`).
Documentation coverage of every definition is checked by
`make doc-check` (ADR-0015).

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
