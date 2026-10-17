# ADR-0017: ledger — Nim service over immudb's REST API and librdkafka's C API, counting by successor calls until P3.3

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-17 |
| Deciders | Transaction Integrity Office (TIO), Platform Enablement Guild (PEG) |
| Step | P1.7 |

## Context

`CLAUDE.md` assigns `ledger` Nim and immudb: it appends every result to a
hash chain (3, step 10; hash rule ADR-0013) and announces it as
`aaas.ledger.appended.v1` (4.2). In phase 1 the saga does not exist yet, so
P1.7 also makes the ledger consume `aaas.addition.requested.v1`, call the
successor `b` times (`TEMPORARY(P3.3)`) and answer
`GET /api/v1/tasks/{taskId}` (`TEMPORARY(P3.3)`; the gateway already routes
it to `ledger:8080`, ADR-0012).

Nim has neither an immudb client nor a maintained Kafka client, and no
mature gRPC library (immudb's native protocol is gRPC). An addition is up
to 99 999 successor calls, so the cost of one call is the waiting time of
the product. The service must survive restarts without counting or
recording anything twice.

## Decision

- **Toolchain.** Nim 2.2.12 from the official `nimlang/nim` image (Debian
  bookworm, linux/amd64 and linux/arm64): it carries the whole
  distribution, including `nimpretty`, the `nim doc` assets and
  `dist/checksums` (SHA-256). Alpine's `nim` package (2.2.0) lacks the doc
  assets, so `nim doc --project` fails there. The runtime is Debian
  bookworm slim with `librdkafka1` 2.0.2 (the version of the successor
  image) and `wget`; the executable is 1.3 MB, the image 150 MB. No Nimble
  package is used: HTTP server and client, JSON, async I/O and unit tests
  come from the standard library. The process is single-threaded (one
  `asyncdispatch` event loop, `--threads:off`).
- **immudb through REST v1.** immudb 1.11.2 serves the gRPC service also as
  JSON under `/api` on its web server (port 8080). The ledger uses
  `/api/login` and `/api/db/use/{db}` (session token, renewed on an
  authentication error), `/api/db/sqlexec` (statements with named
  parameters, `BEGIN TRANSACTION … COMMIT` in one call) and
  `/api/db/sqlquery`. Requests share one keep-alive connection, one at a
  time, with a 2 s deadline and 3 attempts (CLAUDE.md 6.1). The PostgreSQL
  wire protocol of immudb is disabled (`IMMUDB_PGSQL_SERVER=false`), and so
  is dev mode, which the image enables by default.
- **Provisioning.** A one-shot container `ledger-db-init`
  (`curlimages/curl`, `services/ledger/immudb/provision.sh`) creates the
  database `ledger` and the read-write user `ledger` with the superadmin
  credentials (`LEDGER_DB_ADMIN_PASSWORD`); the service only holds its own
  user. The script is idempotent. The immudb image has no shell, so the
  health check is `immuadmin status`.
- **Schema.** SQL migrations in `migrations/`, applied at startup, each in
  one transaction with its row in `schema_migrations`; comment lines are
  stripped (immudb SQL rejects `--`). immudb has no `COMMENT ON`, so the
  table `schema_documentation` describes every table and column, and a
  store test compares it with `TABLES()` and `COLUMNS()`. `sequence` is a
  reserved word in immudb: the column is `entry_seq`. Entries and
  publications are insert-only; immudb keeps every version of the updated
  `tasks` rows.
- **Idempotency.** The consumed event and its task are stored in one
  transaction before the offset is committed; `eventId` is the idempotency
  key and `taskId` the unit of work (a republished event with a new
  `eventId` for a known task is recorded and ignored). Unique keys make
  every write safe to repeat after a timeout: `processed_events.event_id`,
  `tasks.task_id`, `ledger_entries.entry_seq` and `ledger_entries.task_id`
  (one entry per task), `publications.entry_seq`.
- **Counting (`TEMPORARY(P3.3)`).** Each task runs concurrently with the
  others with its own keep-alive connection to the successor; the only
  native `+` is the loop counter. A checkpoint (`done`, `current`) every
  1 000 calls, the interval of the saga's continue-as-new, lets a restart
  resume instead of starting over; repeating a call is safe because the
  successor answers a repeated `(taskId, n)` from its call log (ADR-0016).
  Transient failures are retried with exponential backoff (100 ms doubling
  to 5 s, full jitter) without a limit until P3.6 (`TEMPORARY(P3.6)`); a 4xx
  marks the task `FAILED`.
- **Appending.** One append at a time under an in-process async lock
  (`TEMPORARY(P3.5)`: the etcd lock `ledger-append` from P3.5); the entry
  and the task status are one transaction; the event is published under
  the same lock and recorded in `publications` once acknowledged, so
  entries after the highest published one are the unpublished ones and are
  republished at startup.
- **Kafka over librdkafka's C API.** The functions are imported with Nim's
  FFI. Every callback (delivery reports, errors, statistics and, with
  `log.queue=true`, logs) is served by the poll calls of the event loop, so
  no librdkafka thread ever calls into Nim. `publish` returns a future
  completed by the delivery report; the producer is idempotent with
  `acks=all`. The `broker` health check comes from the statistics (a known
  broker `UP` within the last 5 s). The callback signatures differ from
  the header only in `const` qualifiers, which GCC reports as an error;
  that diagnostic is turned off for that one C file.
- **TCP_NODELAY.** `std/httpclient` writes the headers and the body of a
  request separately; with Nagle's algorithm the body waits for the
  delayed ACK of the server (40 ms). Measured against the successor: 49.9 ms
  per call without and 2.0 ms with `TCP_NODELAY`. The client does not
  expose its socket, so `std/importutils.privateAccess` reaches it after
  the first request of each connection (`ledger/nodelay`).
- **Tooling.** `nimpretty --indent:2 --maxLineLen:100` (lint compares a
  formatted copy), `nim check` with `--styleCheck:error` and no warning or
  unused declaration allowed. Documentation coverage: Nim has no coverage
  tool, so `tools/doc_coverage.nim` checks the `nim jsondoc --docInternal`
  output of every module for the fields of CLAUDE.md 6.5.3 (routines,
  types, values; an example for every exported routine, either
  `runnableExamples`, run by `nim doc`, or an `Example:` field); bindings
  of C symbols (`importc`) only need a description naming the C symbol.
- **Licence of immudb.** immudb is under the Business Source License 1.1
  since 1.9DOM.2: free of charge, production use granted for anything that
  is not a competing paid offering, each release Apache-2.0 four years
  after publication. The last Apache-2.0 image, `1.9DOM.1` (2023), exists
  only for linux/amd64. AaaS uses immudb free of charge and offers nothing
  commercial, which `CLAUDE.md` 1, rule 3 ("open source / free") allows;
  the deviation from an OSI licence is registered as R-016.

## Consequences

- The first addition runs end to end in phase 1: `2 + 3` is `RECORDED`
  0.7 s after `=`; `1000 + 1000` takes 2.3 s (2.3 ms per call), so
  `99999 + 99999` needs about 4 minutes until P2.13 adds the digit
  services to each successor call.
- The ledger uses 3–4 MiB; immudb about 140–160 MiB.
- Removing the temporary parts: P3.3 moves counting and the task status to
  the saga-orchestrator; P3.4
  switches the consumed topic to `aaas.result.voted.v1`; P3.5 replaces the
  in-process lock; P3.6 sends malformed events and exhausted retries to the
  DLQ; P3.7 adds `GET /api/v1/ledger/verify` over `ledger_entries`.
- Changing the immudb passwords after the volume is created has no effect
  (RUNBOOK.md §3.3).
- `make up` builds only missing images (CLAUDE.md 6.6): after
  `make prune-stages` rebuilding every image would rebuild every
  toolchain.
