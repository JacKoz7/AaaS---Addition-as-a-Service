# Redpanda — event bus

| Field | Value |
| --- | --- |
| Document | Infrastructure README |
| Component | Redpanda, Redpanda Console (shared infrastructure, profile `core`) |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Related | `CLAUDE.md` 4.2, [ADR-0011](../../docs/adr/0011-event-bus-redpanda.md), [`compose/core.yml`](../../compose/core.yml), [topic registry](../../contracts/events/topics.psv) |

## 1. Role

Redpanda carries every event of the addition flow (`CLAUDE.md` section 3)
between services through the Kafka API. It is shared infrastructure: it does
not count towards the 35 services and is owned by the Platform Enablement
Guild.

## 2. Containers

| Compose service | Image | Networks | Host port | Memory | Purpose |
| --- | --- | --- | --- | --- | --- |
| `redpanda` | `redpandadata/redpanda:v26.2.4` | `services` | none | 768 MB | Single broker; Kafka API `redpanda:9092`, Admin API `redpanda:9644` |
| `redpanda-topics` | `redpandadata/redpanda:v26.2.4` | `services` | none | 64 MB | One-shot job running `create-topics.sh`, exits 0 when the topics match the registry |
| `redpanda-console` | `redpandadata/console:v3.12.0` | `public`, `services` | `127.0.0.1:8082` | 128 MB | Web UI for topics, messages and consumer groups |

Health checks: the broker reports `Healthy: true` in `rpk cluster health`;
the Console answers `GET /admin/health`. The Console starts only after the
topic job completed successfully, so `make up` returns when the topics exist.

## 3. Topics

The topics are declared in [`contracts/events/topics.psv`](../../contracts/events/topics.psv)
and listed with their producers and consumers in the event catalog of the
documentation portal. Every topic has 3 partitions (messages keyed by
`taskId`), replication factor 1, `cleanup.policy=delete` and seven days of
retention. Automatic topic creation is disabled on the broker.

[`create-topics.sh`](create-topics.sh) reconciles the broker with the
registry:

| Situation | Default run | `--check` |
| --- | --- | --- |
| Topic missing | created | reported, exit 1 |
| Fewer partitions than declared | partitions added | reported, exit 1 |
| More partitions than declared | error, exit 1 (partitions cannot be removed) | reported, exit 1 |
| `cleanup.policy` or `retention.ms` differs | restored | reported, exit 1 |
| Topic on the broker but not in the registry | left alone | not reported |
| Malformed registry row | exit 2 before contacting the broker | exit 2 |

## 4. Operating

```sh
make up PROFILES=core     # broker, topic job and Console
make topics-check         # verify the topics against the registry
make topics               # create or reconcile after editing the registry
open http://127.0.0.1:8082
docker compose exec redpanda rpk topic list
docker compose exec redpanda rpk topic consume aaas.expression.submitted.v1 -n 1
```

`make down` keeps the data volume `aaas_redpanda-data`; `make clean` removes
it together with every event.

## 5. Adding a Topic

1. Add a row to `contracts/events/topics.psv` (a breaking change of an event
   is a new `.v<N+1>` row; existing names never change).
2. Commit it as `contract(contracts): ...`, together with its JSON Schema
   from step P1.3 on.
3. `make topics` on a running broker, or `make up`, creates it.

## 6. Memory

Measured on Docker Desktop (arm64), after producing and consuming 20 000
messages: broker 154 MiB of 768 MiB, Console 59 MiB of 128 MiB. The topic
job runs for a few seconds per start. See ADR-0011 for the reasoning behind
the limits.
