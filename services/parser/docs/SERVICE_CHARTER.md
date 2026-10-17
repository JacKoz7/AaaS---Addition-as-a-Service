# Service Charter — `parser`

| Field | Value |
| --- | --- |
| Document | Service Charter |
| Component | `parser` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Service Version | 0.1.0 |
| Last Reviewed | 2026-10-17 |
| Review Cadence | On every minor version of the service, and at least once per phase |

## 1. Mission

Turns the text expression into an AST.

The parser consumes every expression submitted with `=`
(`aaas.expression.submitted.v1`), decides whether it is an addition of two
numbers, and if so requests that addition from the computation
(`aaas.addition.requested.v1`), exactly once per submitted expression. It
is step 4 of the request flow (`CLAUDE.md` 3) and does nothing else.

## 2. Business Value

AaaS exists to add two non-negative integers with a level of rigour no native
`+` operator can offer. `parser` contributes to that proposition as
described below.

The parser guarantees **correctness of the input** of every addition: only
an expression of exactly the shape `number + number` reaches the arithmetic,
with its operands in the order the user typed them. It also guarantees
**consistency**: a redelivered or retried event never requests the same
addition twice with a different event identifier. Without the parser, the
deliberately unopinionated expression-assembler would forward `2++3` to the
Peano machinery, which has no opinion on the matter either.

## 3. Stakeholders

| Stakeholder | Interest |
| --- | --- |
| Arithmetic Excellence Center (AEC) | Owns, builds and operates the service |
| End user of the calculator | Receives a correct result of the addition |

| Customer Experience Tribe (CXT) | Owns `expression-assembler`, the producer of the consumed events |
| Transaction Integrity Office (TIO) | Owns the consumers of the produced events (`ledger` until P3.4, `saga-orchestrator`) |
| Platform Enablement Guild (PEG) | Operates Redpanda, the event bus of both topics |

## 4. Scope

### In Scope

- Consume `aaas.expression.submitted.v1` idempotently (by `eventId`).
- Parse the expression with the grammar `number "+" number` and record a
  precise rejection reason for anything else.
- Cache the AST of every successfully parsed expression text.
- Publish `aaas.addition.requested.v1` keyed by `taskId`, continuing the
  trace of the consumed event.
- Until P2.17: refuse operands outside the contract range 0–99 999.
- Serve `GET /health` and `GET /metrics`.

### Out of Scope

- Any user-visible feature beyond the calculator keypad, display, timer and
  invoice download (CLAUDE.md section 1).
- Access to the database of any other service (CLAUDE.md section 1, rule 4).

- Assembling expressions from key presses (`expression-assembler`).
- The range rule of operands, from P2.17 (`validator`).
- Ordering the operands so that `b` is the smaller one (`commutator`, P2.15).
- Resolving the operator to a saga and checking the feature flag
  (`operator-registry`, P2.16).
- Reporting a rejected task as `FAILED` to the user (the saga, from P3.6).

## 5. Key Performance Indicators

| KPI | Definition | Target | Source |
| --- | --- | --- | --- |
| Availability | Share of successful `GET /health` probes | See SLO.md | Prometheus |

| Events processed | Consumed events by outcome | Every event has exactly one outcome | `parser_events_consumed_total{outcome}` |
| Duplicate suppression | Redelivered events that did not produce a second request | 100% | `parser_events_consumed_total{outcome="duplicate"}` |
| Rejections by reason | Expressions that are not a valid addition | Reported, not targeted | `parser_expressions_rejected_total{reason}` |
| AST cache hit ratio | Hits / all lookups | Reported, not targeted | `parser_ast_cache_lookups_total{result}` |
| Processing failures | Attempts retried after a database or broker error | 0 in normal operation | `parser_processing_failures_total` |

## 6. Related Documents

[RACI](RACI.md) · [SLO](SLO.md) · [Runbook](RUNBOOK.md) ·
[Threat Model](THREAT_MODEL.md) · [Data Classification](DATA_CLASSIFICATION.md) ·
[Dependencies](DEPENDENCIES.md) · [Capacity](CAPACITY.md) · [API](API.md) ·
[Changelog](CHANGELOG.md) · [README](../README.md)
