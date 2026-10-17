# Release Notes — Phase 1: End-to-End Skeleton

| Field | Value |
| --- | --- |
| Document | Phase Release Notes |
| Phase | 1 — End-to-end skeleton |
| Date | 2026-10-17 |
| Status | Released |
| Milestone | **M1** — `2+3=5` goes through the gateway and the frontend shows the result |
| Tag | `phase-1-done` |
| Steps | P1.1 – P1.9 |
| Owning Team | Platform Enablement Guild (PEG), with AEC, TIO and CXT |
| Classification | INTERNAL |

## Announcement

We are thrilled to announce the completion of Phase 1 of AaaS — Addition as
a Service, and with it the organisation's first milestone. For the first
time in its history, a user can open the calculator, press `2`, `+`, `3`
and `=`, and watch the platform answer `5`, a little over one second
later.

Behind that single digit stand an event bus, a gateway, four event
contracts, a gateway, four microservices in C#, OCaml, Haskell and Nim, a
calculator page in plain JavaScript, four databases and an immutable,
hash-chained ledger in which the result is now permanently recorded. The sum was not computed by a
native `+`: it was reached by three calls of the successor service, exactly
as Peano intended.

## What Is Included

| Step | Delivered |
| --- | --- |
| P1.1 | Redpanda and Redpanda Console in the `core` profile; topic registry `contracts/events/topics.psv` and idempotent topic creation (ADR-0011) |
| P1.2 | `gateway` (Traefik, Go plugin `edge`): file-based routes for `/api` and `/`, RFC 9457 problems, health endpoint (ADR-0012) |
| P1.3 | Event envelope and JSON Schemas of `expression.submitted`, `addition.requested`, `result.voted`, `ledger.appended`, with contract tests in CI (ADR-0013) |
| P1.4 | `expression-assembler` (C#, SurrealDB): `POST /api/v1/keys`, ordered key presses per session, `Idempotency-Key` on `=`, `202 {taskId}` (ADR-0014) |
| P1.5 | `parser` (OCaml, SQLite): consumes `expression.submitted`, builds the AST, publishes `addition.requested` (ADR-0015) |
| P1.6 | `successor` (Haskell, CouchDB): `n + 1` with a call log and `aaas.successor.called.v1` (ADR-0016) |
| P1.7 | `ledger` (Nim, immudb): counts `b` successor calls with checkpoints, appends the result to the hash chain, publishes `ledger.appended`, serves the task status (ADR-0017) |
| P1.8 | Temporary calculator page (`frontend/shell`, plain JavaScript, nginx): keypad, display, browser event bus (ADR-0018) |
| P1.9 | End-to-end tests with Playwright, `make e2e`: `2+3=5`, `0+0`, `9+1`, `99999+1`, `C`, idempotent `=` (ADR-0019) |

Alongside the steps: a disk budget for the workstation (`make disk`,
`make prune-stages`, `COMPONENTS=`, `CLAUDE.md` 6.6) and `make up` that
builds only missing images.

## Business Impact

Phase 1 turns the foundation of Phase 0 into a working product. Every
addition now travels the full path of `CLAUDE.md` 3 that exists so far: key
presses through the gateway, the expression assembled and announced on the
event bus, parsed, counted by successor calls, recorded in a tamper-evident
ledger and shown to the user. Measured on the reference workstation:
`2 + 3` in 1.2 s from `=` to the display, `1000 + 1000` in 2.3 s of
counting, about 2.3 ms per successor call. The services of this phase use
between 4 MiB (ledger) and 52 MiB (expression-assembler) of memory each;
the whole running system, with its databases and Redpanda, about 0.95 GB.
Every component has its ten documents, 100% documentation coverage and a
green CI run.

## Known Limitations

- The ledger counts and serves the task status itself (`TEMPORARY(P3.3)`)
  until the saga-orchestrator exists; the successor computes `n + 1`
  natively (`TEMPORARY(P2.13)`) until the digit services and `carry` exist.
- No validator and no commutator yet: operands are range-checked by the
  parser (`TEMPORARY(P2.17)`) and `b` is the second operand as typed, so
  `1 + 99999` takes 99 999 successor calls.
- A rejected expression (`2++3`) is shown as `Error` only after 15 s
  (`TEMPORARY(P3.6)`: no dead-letter service yet).
- The calculator page is temporary (`TEMPORARY(P8.15)`); it has no waiting
  timer and no invoice button yet. No login or rate limits (Phase 6).
- `make e2e` runs locally, not in CI (ADR-0019).

## What Comes Next

Phase 2 — Digits, carries and parsing (M2): gRPC contracts, the ten digit
services in ten languages, `carry`, `validator`, `commutator` and
`operator-registry`, so that `n + 1` is computed by the digit services with
real carries.
