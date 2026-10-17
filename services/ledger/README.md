# ledger

| Field | Value |
| --- | --- |
| Owning team | Transaction Integrity Office (TIO) |
| Language | Nim 2.2 (ADR-0017) |
| Database | immudb 1.11.2 (`ledger-db`, volume `ledger-data`) |
| Compose profile | `services` |
| Networks | `services`, `data` |
| Ports (container) | 8080 HTTP (no gRPC API) |
| Version | 0.1.0 |

## Role

Immutable hash-chained record of every result.

Step 10 of the request flow (`CLAUDE.md` 3): every result becomes one entry
of a hash chain in immudb, `hash = sha256(prevHash|taskId|a|b|result|recordedAt)`
(ADR-0013), announced as `aaas.ledger.appended.v1` for the stopwatch and
billing.

Until the saga exists the ledger also does the work of steps 5 to 7 and 12:

- it consumes `aaas.addition.requested.v1` instead of `aaas.result.voted.v1`
  (`TEMPORARY(P3.4)`);
- it computes `a + b` itself as `b` calls of the successor service
  (`TEMPORARY(P3.3)`), with a checkpoint every 1 000 calls;
- it answers `GET /api/v1/tasks/{taskId}` for the display (the gateway's
  `tasks` upstream, `TEMPORARY(P3.3)`);
- one append at a time is guaranteed by an in-process lock instead of the
  etcd lock `ledger-append` (`TEMPORARY(P3.5)`);
- malformed events are logged and skipped instead of going to the DLQ
  (`TEMPORARY(P3.6)`).

If the ledger is down, nothing is lost: events wait in Redpanda, counting
tasks resume from their last checkpoint and unpublished entries are
published again at startup.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `GET /api/v1/tasks/{taskId}` | in (through the gateway) | `200 { taskId, status, a, b, progress: { done, total }, result? }`; problems 400, 404, 503 |
| HTTP | `GET /health` | in | `{ "status", "checks": { "database", "broker" } }`, 503 on a failed check |
| HTTP | `GET /metrics` | in | Prometheus text format, metrics prefixed `ledger_` |
| HTTP | `POST /v1/next` of `successor` | out | `{ "n", "taskId" }` → `{ "n": n + 1 }`, `b` times per task |
| Event | `aaas.addition.requested.v1` | in (group `ledger`) | [schema](../../contracts/events/aaas.addition.requested.v1.schema.json) |
| Event | `aaas.ledger.appended.v1` | out (key `taskId`) | [schema](../../contracts/events/aaas.ledger.appended.v1.schema.json) |

`status` is `COUNTING`, `RECORDING`, `RECORDED` or `FAILED` (the statuses of
`CLAUDE.md` 4.1 the ledger can observe); `result` is present for
`RECORDED`. A task is unknown (404) until the ledger has consumed its event,
and, until P3.6, forever for an expression the parser rejected. The trace
of the event is continued in the successor calls, the log lines and the
published event. Details: [docs/API.md](docs/API.md).

## Processing

1. **Accept.** Decode the event, then store it in `processed_events` and,
   for a new task, a `COUNTING` row in `tasks`, in one transaction; then
   commit the offset. A known `eventId` is a duplicate; a new `eventId` for a
   known task (the parser republishes after losing its database) is
   recorded and ignored.
2. **Count.** `b` successor calls from `a`, every task concurrently, one
   keep-alive connection per task. A 503, a 5xx, a timeout (2 s) or a
   connection error is retried with exponential backoff and jitter; a 4xx
   marks the task `FAILED`. Every 1 000 calls the progress is checkpointed.
3. **Append.** Under the append lock: link to the last entry, hash, insert
   the entry and mark the task `RECORDED`, in one transaction.
4. **Announce.** Publish `aaas.ledger.appended.v1`, wait for the broker's
   acknowledgement, record it in `publications`.

## Database

immudb 1.11.2 (`codenotary/immudb`), used through the REST API v1 of its web
server (SQL with named parameters, ADR-0017). The one-shot container
`ledger-db-init` ([`immudb/provision.sh`](immudb/provision.sh)) creates the
database `ledger` and the read-write user `ledger` with the superadmin
credentials, which the service never sees. Migrations are SQL files in
`migrations/`, applied at startup in name order, each in one transaction
with its row in `schema_migrations`. immudb has no `COMMENT ON`: every table
and column is described in the table `schema_documentation` (a test checks
that nothing is missing).

| Table | Content |
| --- | --- |
| `processed_events` | One row per consumed event: `event_id`, `task_id`, `topic`, `processed_at` |
| `tasks` | One row per task: operands, `status`, checkpoint (`done`, `current`), `result`, `traceparent`, `failure`, timestamps |
| `ledger_entries` | The hash chain, insert-only: `entry_seq` (the event's `sequence`), task, operands, `result`, `recorded_at`, `prev_hash`, `hash`, the published event |
| `publications` | Insert-only: `entry_seq` and `published_at` of each acknowledged publication |
| `schema_documentation` | Description of every table and column |
| `schema_migrations` | Applied migrations |

immudb keeps every version of every row and never deletes anything
(R-015): a task row has one version per checkpoint.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `ledger` | Service name used in logs, Kafka client id |
| `AAAS_ENV` | `local` | Environment name (sent to config-server from P5.2) |
| `AAAS_BOOTSTRAP` | `env` | Only `env` until P5.2; `platform` is refused |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_KAFKA_BROKERS` | `redpanda:9092` | Kafka bootstrap servers |
| `AAAS_CONSUMER_GROUP` | `ledger` | Consumer group of the committed offsets |
| `AAAS_DB_URL` | `http://ledger-db:8080` | immudb web server |
| `AAAS_DB_NAME` | `ledger` | immudb database |
| `AAAS_DB_USER` | `ledger` | immudb user |
| `LEDGER_DB_PASSWORD` | (required) | Its password (moves to OpenBao in P5.3) |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Migration files |
| `AAAS_SUCCESSOR_URL` | `http://successor:8080` | Successor base URL |
| `AAAS_CHECKPOINT_EVERY` | `1000` | Successor calls between checkpoints (1–100 000) |
| `AAAS_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` or `fatal` |
| `AAAS_KAFKA_LOG_LEVEL` | `4` | librdkafka log level (0–7); its lines are written as JSON |

`ledger-db` and `ledger-db-init` also read `LEDGER_DB_ADMIN_PASSWORD`, the
immudb superadmin password, applied when the volume is created.

## Running and testing

```sh
make build-ledger         # image through Compose (root Makefile)
make test-ledger          # unit tests, contract check, then store tests on a throw-away immudb
make lint-ledger          # nimpretty check, nim check without warnings or unused declarations
make fmt-ledger           # format sources in place with nimpretty
make doc-coverage-ledger  # nim doc (runs the examples) and tools/doc_coverage.nim: 100%
make api-docs-ledger      # nim doc HTML to build/api-docs/ledger
make logs SVC=ledger
```

`make test-ledger` builds the `test` stage (33 unit tests, among them the
successor client against a local fake server, and the JSON Schema check of
the events the tests built), then starts a throw-away immudb on a private
network, provisions it with `immudb/provision.sh` and runs the 12 store
tests against it.

Try it after `make up` (an addition through the gateway, then its status):

```sh
S=$(uuidgen | tr 'A-Z' 'a-z'); n=0
for k in 2 + 3; do
  curl -s -X POST http://127.0.0.1/api/v1/keys -H 'Content-Type: application/json' \
    -d "{\"sessionId\":\"$S\",\"key\":\"$k\",\"seq\":$((n++))}"
done
T=$(curl -s -X POST http://127.0.0.1/api/v1/keys -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $(uuidgen)" -d "{\"sessionId\":\"$S\",\"key\":\"=\",\"seq\":3}" \
  | sed 's/.*"taskId":"\([^"]*\)".*/\1/')
sleep 1; curl -s http://127.0.0.1/api/v1/tasks/$T
# {"taskId":"...","status":"RECORDED","a":2,"b":3,"progress":{"done":3,"total":3},"result":5}
```

From this directory: `make help`.

## Documents

See `docs/` for the service charter, RACI, SLO, runbook, threat model, data
classification, dependencies, capacity, API reference and changelog.
