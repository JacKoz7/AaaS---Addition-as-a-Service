# expression-assembler

| Field | Value |
| --- | --- |
| Owning team | Customer Experience Tribe (CXT) |
| Language | C# (.NET 10, ASP.NET Core minimal API) |
| Database | SurrealDB 3.3 (container `expression-assembler-db`) |
| Compose profile | `services` |
| Networks | `services`, `data` |
| Ports (container) | 8080 HTTP (no gRPC) |
| Version | 0.1.0 |

## Role

Turns key presses into an expression and starts a task. It is the first AaaS
service an addition meets (`CLAUDE.md` 3, step 2): every click of the
calculator arrives here through the gateway as `POST /api/v1/keys`, is stored
in SurrealDB and announced as `aaas.key.pressed.v1`. When the user presses
`=`, the service assembles the digits and `+` typed since the last `C` (or
the last `=`), creates a task with a UUIDv7 `taskId`, publishes
`aaas.expression.submitted.v1` and answers `202 { taskId }`. From there the
parser (P1.5) and the stopwatch (P8.16) take over.

If the service is down, no addition can start; additions already submitted
continue, because everything after the expression event is driven by
Redpanda.

## Contracts

| Kind | Name | Direction | Contract |
| --- | --- | --- | --- |
| HTTP | `POST /api/v1/keys` | in (via gateway) | `CLAUDE.md` 4.1; details in [docs/API.md](docs/API.md) |
| HTTP | `GET /health` | in | `{ "status": "ok", "checks": { "database": "ok", "broker": "ok" } }`, 503 when a check fails |
| HTTP | `GET /metrics` | in | Prometheus text format |
| Event | `aaas.key.pressed.v1` | out | [schema](../../contracts/events/aaas.key.pressed.v1.schema.json), keyed by `sessionId` |
| Event | `aaas.expression.submitted.v1` | out | [schema](../../contracts/events/aaas.expression.submitted.v1.schema.json), keyed by `taskId` |

Behaviour in short (full table in [docs/API.md](docs/API.md)):

- every key press is stored once per `(sessionId, seq)`; a retry with the same
  key is accepted again (204), a different key at the same `seq` is a 409;
- `=` requires `Idempotency-Key`; the same key returns the same task (202),
  a key reused for another press is a 409;
- an empty expression or one longer than 64 keys is a 422;
- an unavailable database or broker, or a request that exceeds its 1.8 s
  budget, is a 503 and the client retries the same request, which republishes
  the stored event with the same `eventId`.

Every error is an RFC 9457 problem (`application/problem+json`).

## Database

SurrealDB, accessed over its HTTP RPC endpoint with a token obtained once by
sign-in ([ADR-0014](../../docs/adr/0014-expression-assembler-surrealdb-and-kafka.md)).
The service never reads another service's database.

| Table | Record key | Content |
| --- | --- | --- |
| `key_press` | `[sessionId, seq]` | key, reception time, the serialized key press event, published flag, task created by an `=` |
| `task` | `taskId` | session, `seq`, expression, `Idempotency-Key`, submission time, the serialized expression event, published flag |
| `idempotency_key` | the header value | link to the task; creating an existing key fails, which serialises concurrent retries |
| `migration` | version | applied migrations |

Migrations live in [`migrations/`](migrations/) (`NNNN_name.surql`) and run at
startup, each in one transaction with its `migration` record; every table and
field has a `COMMENT`. Data is kept until the volume is removed (`make clean`);
see [docs/DATA_CLASSIFICATION.md](docs/DATA_CLASSIFICATION.md).

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `AAAS_SERVICE` | `expression-assembler` | Service name in logs, metrics and the `producer` of events |
| `AAAS_ENV` | `local` | Environment name |
| `AAAS_BOOTSTRAP` | `env` | Only `env` is supported until P5.2; `platform` stops the service |
| `AAAS_HTTP_PORT` | `8080` | HTTP port |
| `AAAS_KAFKA_BROKERS` | — (required) | Kafka bootstrap servers, `redpanda:9092` in Compose |
| `AAAS_DB_URL` | — (required) | SurrealDB URL, `http://expression-assembler-db:8000` in Compose |
| `AAAS_DB_USER` | `expression_assembler` | SurrealDB user (also given to the database container) |
| `EXPRESSION_ASSEMBLER_DB_PASSWORD` | — (required; `change-me` in `.env.example`) | SurrealDB password (moves to OpenBao in P5.3) |
| `AAAS_DB_NAMESPACE` | `aaas` | SurrealDB namespace |
| `AAAS_DB_NAME` | `expression_assembler` | SurrealDB database |
| `AAAS_MIGRATIONS_DIR` | `/app/migrations` | Migration files |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | unset | When set, traces are exported over OTLP (collector from P7.1) |

## Running and testing

```sh
make build-expression-assembler   # image through Compose (root Makefile)
make test-expression-assembler    # 72 xUnit tests, including SurrealDB and contract tests
make lint-expression-assembler    # dotnet format check and analyzers (warnings are errors)
make fmt-expression-assembler     # dotnet format in place
make doc-coverage-expression-assembler  # CS1591 + StyleCop SA1600-SA1602, private members included
make api-docs-expression-assembler      # DocFX site to build/api-docs/expression-assembler
make logs SVC=expression-assembler
```

The test stage copies the SurrealDB binary from the database image and
starts it in memory for the storage tests, and receives `contracts/` as a
named build context for the contract tests. From this directory: `make help`.

Try it after `make up`:

```sh
S=$(uuidgen | tr 'A-Z' 'a-z')
for k in 2 + 3; do
  curl -s -X POST http://127.0.0.1/api/v1/keys -H 'Content-Type: application/json' \
    -d "{\"sessionId\":\"$S\",\"key\":\"$k\",\"seq\":$((n++))}"
done
curl -s -X POST http://127.0.0.1/api/v1/keys -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $(uuidgen)" -d "{\"sessionId\":\"$S\",\"key\":\"=\",\"seq\":3}"
```

## Documents

See `docs/` for the [service charter](docs/SERVICE_CHARTER.md),
[RACI](docs/RACI.md), [SLO](docs/SLO.md), [runbook](docs/RUNBOOK.md),
[threat model](docs/THREAT_MODEL.md),
[data classification](docs/DATA_CLASSIFICATION.md),
[dependencies](docs/DEPENDENCIES.md), [capacity](docs/CAPACITY.md),
[API reference](docs/API.md) and [changelog](docs/CHANGELOG.md).
