# ADR-0016: successor — Haskell service over HTTP/JSON until P2.1, CouchDB call log keyed by task and argument

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-17 |
| Deciders | Arithmetic Excellence Center (AEC), Platform Enablement Guild (PEG) |
| Step | P1.6 |

## Context

`CLAUDE.md` assigns `successor` Haskell and CouchDB: it computes `n + 1`
(natively until P2.13, then through the digit services and `carry`), logs
every call in CouchDB (3, step 7) and is the producer of
`aaas.successor.called.v1` (4.2). Its contract is the gRPC method
`Next({n}) → {n}` (4.3), but the `.proto` files, `buf` and the code
generation for Haskell only arrive in P2.1. An addition `a + b` calls the
successor `b` times, up to 99 999 times in a row, so the latency of one
call is the latency of the product (estimated 10–20 ms, `CLAUDE.md` 1).

Open questions: the interface before P2.1, what makes a retried call safe,
how CouchDB is configured and migrated, how the event is published, how the
documentation rules of 6.5 map to Haskell, and which formatter and linter
apply.

## Decision

- **HTTP/JSON until P2.1.** `POST /v1/next` with
  `{"n": <integer>, "taskId": <uuid>}` answers `{"n": n + 1}`: the same
  method and message shape as `Next`, plus the task the call belongs to,
  which the call log and the event need. Problems follow RFC 9457 (400
  malformed body, 422 argument outside `0..199997` or malformed `taskId`,
  503 dependency failure). The handler is marked `TEMPORARY(P2.1)`; P2.1
  adds the gRPC service on port 9090 and the callers move to it.
- **Natural key of a call.** An addition computes the successor of each
  value from `a` to `a + b − 1` exactly once, so `<taskId>:<n>` identifies
  a call. The call log document has this `_id`; a retried call (client
  timeout, 503) finds its document (HTTP 409), answers the stored result
  and publishes the stored event again, so neither a second document nor a
  second `eventId` is ever created. The event is stored as text in the
  document before it is published.
- **Answer after both side effects.** The call log write comes first, then
  the publication, which waits for the broker's acknowledgement (idempotent
  producer, `acks=all`, 1 s message timeout); the answer is sent after
  both. A caller that saw a success can therefore rely on the audit trail.
  The request budget is 1.8 s, as in ADR-0014: CouchDB calls have 250 ms
  per attempt, three attempts with jitter (50 ms, 100 ms).
- **CouchDB 3.5.1, single node, own image.** `successor-db` is built from
  `services/successor/couchdb/Dockerfile`: the official image plus
  `10-aaas.ini` (`single_node = true`, `[cluster] n = 1`, log level
  `warning`). A bind mount is not used: the image's entry point changes the
  owner of its configuration files, which fails on a read-only mount and
  would change the owner of the host file on Linux. HTTP Basic
  authentication is used: CouchDB 3.5 caches verified credentials, and a
  write cost 4 ms with Basic authentication and with a session cookie
  alike.
- **Migrations as JSON operations.** CouchDB has no DDL; a migration file
  (`migrations/NNNN_*.json`) lists idempotent operations
  (`createDatabase`, `putDocument`) and is recorded in the database
  `successor_migrations`. Migration 0001 creates `successor_calls` and the
  design document `_design/call_log` with the view `by_task` and an
  `aaas_documentation` object describing every field, the CouchDB
  counterpart of `COMMENT ON` (`CLAUDE.md` 6.5.3).
- **Delivery reports need polling.** hw-kafka-client fires delivery
  reports only while librdkafka is polled and its producer has no polling
  thread, so the service runs one (`flushProducer` in a loop, a 100 ms
  poll through a safe FFI call) and installs a no-op global delivery
  callback, through which the per-message callbacks are dispatched.
  Without both, no call would ever see its acknowledgement.
- **Stack.** GHC 9.10.3 (`haskell:9.10.3-slim-bookworm`), warp/WAI,
  http-client, aeson, hw-kafka-client 5.3 (librdkafka 2.0.2 of Debian
  bookworm), prometheus-client, hspec. Dependencies are pinned by the
  `index-state` of `cabal.project` and `cabal.project.freeze`. librdkafka's
  log lines are forwarded to the JSON logger through its log callback. The
  runtime image is Debian bookworm slim with `librdkafka1`, `libgmp10`,
  `libffi8` and `wget`; the GHC heap is capped at 40 MB in a 64 MB
  container.
- **Formatting, linting, documentation.** ormolu (check mode) and hlint;
  every component is built with `-Wall … -Werror`. Documentation uses
  Haddock with the fields of `CLAUDE.md` 6.5.3 as bold paragraph headings;
  coverage is measured by Haddock with `--ignore-all-exports`, so private
  definitions count, and must be 100% in every module. Examples are
  doctests (`>>>`) run by `doctest` in the test stage; examples that need
  I/O are written as prose. The doctests run with
  `-Wno-missing-export-lists`, because GHCi's interactive module has no
  export list and the package builds with `-Werror`.
- **Tests.** The hspec suite runs in the Dockerfile test stage with fake
  dependencies; every event the fake publisher receives is validated
  against the JSON Schema (`scripts/validate-events.py --events`, Python
  venv with the jsonschema versions of the documentation image). `make
  test-successor` then runs the CouchDB specs against a throw-away
  `successor-db` container on a private network.
- **New contract.** `aaas.successor.called.v1` gets its schema (payload
  `n`, `result`), and the truth check of `validate-events.py` now also
  requires `result = n + 1`.
- **Header types.** `.cabal` files must start with `cabal-version`, so they
  get their own type with that preamble; `cabal.project` files use the
  Haskell comment style; `.ini` files get a type with `;` comments, the
  only comment syntax CouchDB's configuration parser accepts.

## Consequences

- P1.7 (`ledger`) calls `POST /v1/next` with its `taskId`; P2.1 replaces
  the HTTP method with gRPC and removes `TEMPORARY(P2.1)`.
- Each call costs one CouchDB write and one acknowledged Kafka message;
  the measured latency is recorded in CAPACITY.md and decides the waiting
  time of an addition until P11.1 measures the whole chain.
- A large addition writes up to 99 999 documents (about 3.2 KB each on
  disk before compaction) and as many events; storage grows without a
  retention job (R-014).
- Measured: 2.0 ms per call (p50) and 5.7 ms (p99) with a keep-alive
  caller, so the successor alone needs about 4 minutes for 99 999 calls.
