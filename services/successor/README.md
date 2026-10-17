# successor

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Language | Haskell (GHC 9.10, ADR-0016) |
| Database | CouchDB 3.5.1 (`successor-db`, volume `successor-data`) |
| Compose profile | `services` |
| Networks | `services`, `data` |
| Ports (container) | 8080 HTTP (gRPC 9090 from P2.1) |
| Version | 0.1.0 |

## Role

Computes n+1 through the digit services and carry.

Step 7 of the request flow (`CLAUDE.md` 3): an addition `a + b` is `b`
successor calls, made by the ledger until P3.3 and by the saga afterwards.
Every call is logged in CouchDB and announced as
`aaas.successor.called.v1`. Until P2.13 the successor is computed natively
(`TEMPORARY(P2.13)`); P2.13 replaces that with the digit services and
`carry`. Until P2.1 the method `Next` of `CLAUDE.md` 4.3 is served over
HTTP/JSON (`TEMPORARY(P2.1)`).

If the successor is down, additions stop counting until it is back: the
caller retries its call, and no step is lost.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `POST /v1/next` | in | `{ "n": <0..199997>, "taskId": <uuid> }` → `200 { "n": n + 1 }`; problems 400, 413, 422, 503 |
| HTTP | `GET /health` | in | `{ "status", "checks": { "database", "broker" } }`, 503 on a failed check |
| HTTP | `GET /metrics` | in | Prometheus text format, metrics prefixed `successor_` |
| Event | `aaas.successor.called.v1` | out (key `taskId`) | [schema](../../contracts/events/aaas.successor.called.v1.schema.json) |

A `traceparent` header is continued in the log lines and the event.
Details: [docs/API.md](docs/API.md).

## Processing of one call

1. Validate the body; check `0 <= n <= 199997` (422 otherwise).
2. Write the call log document `<taskId>:<n>` with the result and the
   serialized event. If it already exists (a retried call), read it.
3. Publish the event (the stored one for a retry) and wait for the broker's
   acknowledgement.
4. Answer `{ "n": n + 1 }`.

A failure of CouchDB (after three attempts of 250 ms) or Kafka (1 s message
timeout) answers 503; the caller retries the same call, which is safe
(steps 2 and 3).

## Database

CouchDB 3.5.1, single node, built from [`couchdb/Dockerfile`](couchdb/Dockerfile)
with [`couchdb/10-aaas.ini`](couchdb/10-aaas.ini). The service never reads
another service's database. Migrations are JSON files in `migrations/`
(idempotent `createDatabase` and `putDocument` operations), applied at
startup in name order and recorded in the database `successor_migrations`.

| Database | Content |
| --- | --- |
| `successor_calls` | One document per call, `_id` `<taskId>:<n>`: `taskId`, `n`, `result`, `eventId`, `event` (the published JSON), `calledAt`, `traceId`; view `_design/call_log/_view/by_task` (key `[taskId, n]`); field documentation in `_design/call_log.aaas_documentation` |
| `successor_migrations` | One document per applied migration: `appliedAt`, `description` |

There is no retention job yet (R-014).

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `successor` | Service name used in logs |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` until P5.2; `platform` is refused |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_KAFKA_BROKERS` | `redpanda:9092` | Kafka bootstrap servers |
| `AAAS_DB_URL` | `http://successor-db:5984` | CouchDB base URL |
| `AAAS_DB_USER` | `successor` | CouchDB user |
| `SUCCESSOR_DB_PASSWORD` | (required) | CouchDB password (moves to OpenBao in P5.3) |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Migration files |
| `AAAS_LOG_LEVEL` | `info` | `debug` (one line per call), `info`, `warn`, `error`, `fatal` |
| `AAAS_KAFKA_LOG_LEVEL` | `4` | librdkafka log level (0–7); its lines are written as JSON |

## Running and testing

```sh
make build-successor   # image through Compose (root Makefile)
make test-successor    # hspec, doctests, contract test, then CouchDB specs
make lint-successor    # ormolu check, hlint, -Werror build
make fmt-successor     # format sources in place with ormolu
make doc-coverage-successor  # Haddock coverage, private definitions included
make api-docs-successor      # Haddock HTML to build/api-docs/successor
make logs SVC=successor
```

`make test-successor` builds the `test` stage (21 hspec examples, the
doctests of the documentation, and the JSON Schema check of every event
the tests published), then starts a throw-away `successor-db` container on
a private network and runs the 2 CouchDB specs against it.

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
