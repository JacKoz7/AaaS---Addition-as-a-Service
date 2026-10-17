# ADR-0015: parser — OCaml 4.14 with the librdkafka bindings, SQLite idempotency record and contract-tested output

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-17 |
| Deciders | Arithmetic Excellence Center (AEC), Platform Enablement Guild (PEG) |
| Step | P1.5 |

## Context

`CLAUDE.md` assigns `parser` OCaml and SQLite (an AST cache). The parser
consumes `aaas.expression.submitted.v1`, builds the AST of the expression
and publishes `aaas.addition.requested.v1` (`CLAUDE.md` 3, step 4); in P1.5
it does so without the validator and the commutator, which arrive in P2.14
and P2.15 and are wired in by P2.17. The general rules apply: idempotent
consumers keyed by `eventId` (4.2), port 8080 with `/health` and
`/metrics`, JSON logs, trace propagation, migrations at startup, timeouts
and three attempts, graceful shutdown within 10 s (6.1), and a 64 MB limit
for compiled languages (6.2).

Open questions: which Kafka client OCaml can use, which OCaml version
follows from it, how consumption and offsets work without a balanced
consumer group, what happens to expressions that are not additions or are
outside the contract range while the validator does not exist yet, how a
retry avoids publishing a second event for the same task, how the
documentation rules of `CLAUDE.md` 6.5 map to odoc, and how a producer
proves that what it publishes matches the schema.

## Decision

- **Kafka through the `kafka` opam bindings (librdkafka), OCaml 4.14.**
  `kafka` 0.5 with `kafka_lwt` is the only maintained-enough OCaml client;
  its latest release requires OCaml < 5.0, so the service is built with
  OCaml 4.14.2 (the long-term branch of 4.x) on
  `ocaml/opam:alpine-3.22-ocaml-4.14`. Every opam package is pinned to an
  exact version in `aaas_parser.opam` and installed from the image's
  repository snapshot without `opam update`. The base image ships opam 2.0,
  which has no `with-dev-setup` filter, so `ocamlformat` is a `with-test`
  dependency. The other libraries are Lwt, cohttp-lwt-unix (HTTP), sqlite3
  and yojson; Alcotest for the tests.
- **Partition consumer, one instance, offsets stored after processing.** The
  bindings expose librdkafka's partition-level consumer, not the
  group-balanced one. The parser therefore reads the partition list of the
  input topic at startup, consumes all partitions through one queue, and
  commits offsets to the consumer group `parser` (`enable.auto.offset.store
  = false`, stored after a message is processed, committed every second and
  when consumption stops). The service must run as a single instance; a
  second one would consume the same partitions (risk R-013). Before the
  Kafka handle is destroyed, the queue and the topic must be destroyed, or
  librdkafka waits forever: the shutdown sequence does that and a watchdog
  ends the process after 9 s regardless.
- **SQLite as the idempotency record and the AST cache.** `processed_events`
  keyed by the consumed `eventId` stores the outcome and, for an addition,
  the serialized output event **before** it is published (`pending`), then
  `published` after the broker acknowledgement. A retry or a redelivery of
  a `pending` event republishes the identical text, so one consumed event
  yields exactly one produced `eventId`; a `published` or `rejected` event
  is skipped. `ast_cache` maps an expression text to its AST (JSON) and
  counts hits. The database runs in WAL mode with `synchronous = FULL`:
  losing a committed row after a crash would publish a second event with a
  new `eventId` for the same task. The file lives in the volume
  `parser-data`; SQLite has no credentials, so the service has no database
  password and is attached to the `services` network only.
- **Grammar and rejections.** The only accepted expression is
  `number "+" number` with any number of digits; leading zeros are
  removed. Every other input is rejected with a code
  (`empty_expression`, `invalid_character`, `missing_operator`,
  `missing_left_operand`, `missing_right_operand`,
  `unexpected_operator`) and the position of the problem. Rejections are
  stored with their reason, logged and counted, and nothing is published.
- **Contract range enforced locally until the validator exists.** An
  operand above 99 999 cannot be published, because the schema of
  `aaas.addition.requested.v1` forbids it; the parser rejects it with
  `operand_out_of_range`. This is marked `TEMPORARY(P2.17)`: from P2.17 the
  validator owns the rule.
- **Retries in place until the dead-letter service exists.** Database and
  broker failures are retried with exponential backoff and jitter (three
  quick attempts, from 0.2 s), then every 5 s, without advancing the offset.
  Messages that are not `aaas.expression.submitted.v1` events and rejected
  expressions are not retried. Both are marked `TEMPORARY(P3.6)`: P3.6
  sends exhausted messages to `aaas.dlq.v1` and lets the saga mark rejected
  tasks as `FAILED`. Until then a rejected task stays without a result.
- **Publication.** Idempotent producer with `acks=all`,
  `message.timeout.ms = 2000` and a 2.5 s guard on the delivery report;
  keyed by `taskId` with librdkafka's default partitioner, the same as the
  expression-assembler's client.
- **Trace context.** The produced event continues the consumed trace: same
  trace identifier and flags, a new span identifier; an absent or invalid
  `traceparent` starts a new sampled trace. Log lines carry `traceId` and
  `spanId` of that span. Exporting spans over OTLP is left to P7.2, which
  instruments every service.
- **Health.** `/health` reports three checks: `database` (`SELECT 1`),
  `broker` (TCP connection to the first broker within 1 s; the bindings
  expose no connection state) and `consumer` (the last poll ended less than
  15 s ago, so a message stuck in retries makes the service unhealthy).
- **Documentation coverage.** Modules are written as `.ml` files without
  `.mli` interfaces, so every definition is documented exactly once, with
  the fields of `CLAUDE.md` 6.5.3 as odoc sections and tags. Presence is
  checked by `scripts/doc-check.sh` (new `ocaml` row: a doc comment must end
  on the line above every top-level `let`, `type`, `exception`, `module`,
  `external`, `class` and `val`; `ocamlformat` keeps doc comments before
  the item with `doc-comments = before`); compiler warning 50 rejects a
  misplaced doc comment, and the odoc build runs with warnings as errors,
  so every cross-reference resolves. References to standard-library
  exceptions are written as code, because the standard library is not part
  of the private documentation build. odoc has no doctest runner for `.ml`
  files, so the examples of the documentation are covered by unit tests of
  the same behaviour rather than executed literally.
- **Header types.** `dune-project` must start with `(lang dune …)`, so it
  gets its own header type with that preamble; `.opam` and `.ocamlformat`
  files use `#` comments and move to the `conf` type.
- **Contract test of the output.** When `PRODUCED_DIR` is set, the unit
  tests write every event the processor publishes to that directory, and
  the Dockerfile test stage validates them with
  `scripts/validate-events.py --events` (new mode) against the schema of
  their topic, with Alpine's `py3-jsonschema`. The consumed side uses the
  valid examples of `aaas.expression.submitted.v1` as fixtures.

## Consequences

- The parser runs on an older OCaml line than the current 5.x; moving to 5.x
  requires a release of the bindings or own librdkafka stubs.
- Throughput is bounded by sequential processing (one message at a time), a
  few milliseconds per expression; scaling out needs a group-balanced
  consumer first (R-013).
- A malformed or out-of-range expression produces a stored, logged and
  counted rejection, but the user sees no result until P3.6 adds the
  failure path.
- Every event the parser publishes in its tests has passed the same JSON
  Schema as the contract examples.
- Future OCaml services can reuse the doc-check row, the header types and
  the Dockerfile layout.
