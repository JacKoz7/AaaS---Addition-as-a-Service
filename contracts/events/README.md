# Event Contracts

| Field | Value |
| --- | --- |
| Document | Contract directory README |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Related | `CLAUDE.md` 4.2, [ADR-0011](../../docs/adr/0011-event-bus-redpanda.md), [Redpanda README](../../infra/redpanda/README.md) |

This directory holds the contracts of the events exchanged on Redpanda.

| File | Content | Since |
| --- | --- | --- |
| [`topics.psv`](topics.psv) | Registry of every topic: partitions, producer, consumers, purpose. Creates the topics on the broker (`infra/redpanda/create-topics.sh`) and feeds the event catalog of the portal. | P1.1 |
| `*.json` | JSON Schema of the event envelope and of each event payload. | P1.3 |

Rules (`CLAUDE.md` 4.2):

- Topic names follow `aaas.<entity>.<past-tense-verb>.v<N>`; messages are
  keyed by `taskId`.
- Events are immutable. An incompatible change is a new topic `.v<N+1>`,
  never an edit of an existing one.
- Every change in this directory is a separate `contract(contracts)` commit.
