# ADR-0014: expression-assembler — SurrealDB over HTTP RPC, Kafka producer and request budget

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-17 |
| Deciders | Customer Experience Tribe (CXT), Platform Enablement Guild (PEG) |
| Step | P1.4 |

## Context

`CLAUDE.md` assigns `expression-assembler` C# and SurrealDB, the public
endpoint `POST /api/v1/keys` (4.1), the events `aaas.key.pressed.v1` and
`aaas.expression.submitted.v1` (4.2), and the general rules of 6.1 and 6.2:
port 8080, JSON logs, migrations at startup, timeouts of 2 s with three
attempts, graceful shutdown within 10 s, default memory limits by language
class. Step 2 of the flow (`CLAUDE.md` 3) requires `=` to carry an
`Idempotency-Key` and to be checked against the idempotency service, which
only arrives in P6.3.

Open questions: how to reach SurrealDB from .NET, how to authenticate, how
to make "one `=`, one task" hold under retries without the idempotency
service, how to keep the response within the gateway's 2 s timeout, which
runtime image works with the Kafka client, and which memory class .NET
belongs to.

## Decision

- **Runtime.** .NET 10 (LTS), ASP.NET Core minimal API on
  `CreateSlimBuilder`. Build stages use the glibc SDK image
  (`sdk:10.0.402-noble`); the runtime is `aspnet:10.0.13-alpine3.24`, which
  has busybox `wget` for the Compose health check. The output is published
  portable (no RID, no app host) so that Confluent.Kafka picks the Alpine
  build of librdkafka, which needs the Alpine package `cyrus-sasl`.
- **SurrealDB access: HTTP RPC without an SDK.** Queries go to `POST /rpc`
  (`method: query`) with typed variables. SurrealDB 3.3.4 with the SurrealKV
  engine; memtable and block cache are reduced to 16 MiB so the store fits
  256 MB. Two engine behaviours shape the queries: some variable names are
  reserved (`$session`, `$event`, `$before`), so neutral names are used; and
  a JSON string that looks like a UUID arrives as a `uuid` value, so
  identifier variables are cast with `<string>`.
- **Token authentication.** The client signs in once (`POST /signin`) and
  sends the token as a bearer header; it renews the token one minute before
  the `exp` claim and once after a 401/403. Basic authentication on every
  request was measured: SurrealDB verifies the password hash per request,
  25–50 ms of CPU each, which made a key press take 1.6 s under a small
  load. With a token a query takes about 1 ms.
- **Exactly one task per `=` without the idempotency service.** Record keys
  carry the natural keys: `key_press:[sessionId, seq]`, `task:⟨taskId⟩`,
  `idempotency_key:⟨key⟩`. Creating an existing record fails with
  `AlreadyExists`, which the store reports as "already there". The task, its
  idempotency key and the link from the `=` press are written in one
  transaction. Concurrent retries therefore converge on one task. The local
  claim is marked `TEMPORARY(P6.3)` in `KeyService`; P6.3 replaces it with
  `Claim`/`MarkFailed`.
- **Stored events, published after storage.** Each press and task stores its
  serialized event and a `published` flag. The event is published after the
  record is stored and the flag is set after the broker acknowledgement. A
  failed publication answers 503; the client's retry publishes the identical
  event (same `eventId`), which consumers deduplicate (`CLAUDE.md` 4.2). There
  is no background republisher: an `=` without a retry yields no task the
  user could see anyway, and the guaranteed-delivery path of the computation
  is the saga outbox (P3.4).
- **Request budget.** Every key request has 1.8 s, below the gateway's 2 s
  response timeout (ADR-0012), so a slow dependency yields this service's
  503 problem rather than a gateway 504. The defaults of `CLAUDE.md` 6.1 are
  shortened accordingly: database calls 500 ms per attempt (three attempts
  with jitter, total 1.7 s, circuit breaker) and Kafka messages 1.5 s
  (1 s per broker request, idempotent producer, `acks=all`). Errors returned
  to clients carry no internal details; causes are logged.
- **Memory class.** .NET compiles to IL executed by a JIT with a garbage
  collector plus a native Kafka client, so the service takes the 128 MB
  default of interpreted languages instead of 64 MB; the GC heap is capped at
  70% of the limit. Measured: 53–55 MiB.
- **Documentation coverage.** CS1591 and StyleCop SA1600–SA1602 as errors
  with `documentPrivateElements` and `documentPrivateFields`; DocFX renders
  the API documentation with private members, excluding code produced by
  .NET source generators.
- **Generated API reference.** The events section of every service
  `docs/API.md` is generated from the topic registry and the schemas
  (`scripts/service-api.py`, `make api-md`) and checked by
  `make contracts-check`, completing what ADR-0013 started for the
  contracts themselves.

## Consequences

- `POST /api/v1/keys` answers in about 11 ms per key and 19 ms for `=`, and
  stays correct under client retries and races (covered by tests against a
  real SurrealDB binary).
- Until P6.3 the idempotency guarantee holds only within this service's
  database; that is sufficient because it is the only service receiving `=`.
- Key presses and tasks accumulate without a retention job (R-012).
- An event that failed to publish and is never retried stays unpublished in
  the database; the `published` flag makes such records findable.
- Any future .NET service can reuse the analyzer setup, the slim host and
  the Alpine runtime with `cyrus-sasl` if it uses Kafka.
