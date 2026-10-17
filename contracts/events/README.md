# Event Contracts

| Field | Value |
| --- | --- |
| Document | Contract directory README |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Related | `CLAUDE.md` 4.2, [ADR-0011](../../docs/adr/0011-event-bus-redpanda.md), [ADR-0013](../../docs/adr/0013-event-envelope-and-schema-conventions.md), [Redpanda README](../../infra/redpanda/README.md) |

This directory holds the contracts of the events exchanged on Redpanda.

| File | Content | Since |
| --- | --- | --- |
| [`topics.psv`](topics.psv) | Registry of every topic: partitions, producer, consumers, purpose. Creates the topics on the broker (`infra/redpanda/create-topics.sh`) and feeds the event catalog of the portal. | P1.1 |
| [`envelope.v1.schema.json`](envelope.v1.schema.json) | JSON Schema 2020-12 of the envelope shared by every event, and the shared types (`$defs`): UUIDv7, millisecond UTC timestamp, operand, sum, SHA-256. | P1.3 |
| `<topic>.schema.json` | Schema of one event: the envelope plus `const` type, version and producer, a non-null `taskId` and a closed payload. Present for [`aaas.key.pressed.v1`](aaas.key.pressed.v1.schema.json) (P1.4), [`aaas.expression.submitted.v1`](aaas.expression.submitted.v1.schema.json), [`aaas.addition.requested.v1`](aaas.addition.requested.v1.schema.json), [`aaas.result.voted.v1`](aaas.result.voted.v1.schema.json) and [`aaas.ledger.appended.v1`](aaas.ledger.appended.v1.schema.json). | P1.3 |
| `examples/<topic>/valid/*.json` | Example events that must pass their schema and be true (`result = a + b`, correct ledger hash). Services may reuse them as test fixtures. | P1.3 |
| `examples/<topic>/invalid/*.json` | Test cases `{"description", "errorAt", "event"}`: the event must fail, with an error at the JSON pointer `errorAt`. | P1.3 |

The schemas and examples are checked by `make contracts-check`
(`scripts/validate-events.py`, also part of `make lint` and the CI job
`contracts`); the conventions it enforces are in
[ADR-0013](../../docs/adr/0013-event-envelope-and-schema-conventions.md).
The portal's event catalog renders the fields of every schema from these
files.

Rules (`CLAUDE.md` 4.2):

- Topic names follow `aaas.<entity>.<past-tense-verb>.v<N>`; messages are
  keyed by `taskId`.
- Events are immutable. An incompatible change is a new topic `.v<N+1>`,
  never an edit of an existing one.
- Schemas are closed (`additionalProperties: false`) and consumers are
  tolerant readers: adding an optional payload field is a compatible change
  in the same schema; adding a required field, removing, renaming or
  narrowing one needs a new topic (ADR-0013).
- A new event schema needs its topic in `topics.psv`, at least one valid and
  one invalid example, and a `description` on every property.
- Every change in this directory is a separate `contract(contracts)` commit.
