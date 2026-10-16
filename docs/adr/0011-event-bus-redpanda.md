# ADR-0011: Event bus — single Redpanda broker and declared topics

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-16 |
| Deciders | Platform Enablement Guild (PEG) |
| Step | P1.1 |

## Context

`CLAUDE.md` section 2 places Redpanda and Redpanda Console in the Compose
profile `core`. Section 4.2 fixes the topics, their naming
(`aaas.<entity>.<past-tense-verb>.v<N>`), partitioning by `taskId`, JSON
payloads validated against schemas held by `schema-registry` (Apicurio,
P3.1), and immutable events where a breaking change means a new `.v2` topic.
Section 6.2 publishes Redpanda Console on host port 8082 and sets memory
defaults that do not name a class for a message broker.

The specification leaves open: how the broker runs on one workstation, how
topics come into existence, their partition count and retention, and what
happens with the features Redpanda bundles besides the Kafka API (an HTTP
proxy and its own schema registry).

## Decision

- **One broker, development-container mode.** Image
  `redpandadata/redpanda:v26.2.4` (multi-arch), started with
  `--mode=dev-container --smp=1 --memory=512M --reserve-memory=0M`. The
  mode relaxes the production checks (fsync batching, CPU pinning) that do
  not apply to a laptop. One broker means replication factor 1; there is no
  failover. Data lives in the volume `redpanda-data`.
- **Only the Kafka API and the Admin API listen.** The Kafka API is
  advertised as `redpanda:9092` on the `services` network; the Admin API
  (`9644`) serves the health check, rpk and the Console. The bundled HTTP
  proxy and schema registry are disabled (`--set pandaproxy=null`,
  `--set schema_registry=null`): AaaS has exactly one schema registry,
  `schema-registry`, and nothing uses an HTTP proxy. No broker port is
  published on the host (`CLAUDE.md` 6.2 lists only the Console).
- **Automatic topic creation is off**
  (`redpanda.auto_create_topics_enabled=false`). A producer writing to an
  undeclared or misspelt topic gets `UNKNOWN_TOPIC_OR_PARTITION` instead of
  silently creating a topic that nobody consumes.
- **Topics are declared in `contracts/events/topics.psv`**, one row per
  topic with its partition count, producer, consumers and purpose. The
  registry is a contract (changed with `contract(contracts)` commits) and
  feeds both the broker and the event catalog of the portal
  (`scripts/docs-portal.py`, ADR-0010), so the documentation lists exactly
  the topics that exist.
- **`infra/redpanda/create-topics.sh`** reconciles the broker with the
  registry with rpk: it creates missing topics, raises partition counts and
  restores drifted configuration; it never deletes a topic and refuses to
  lower a partition count. `--check` verifies without changing anything.
  It runs in the one-shot Compose service `redpanda-topics` (the broker image,
  which ships rpk; the script and the registry are mounted read-only) after
  the broker is healthy. `make topics` and `make topics-check` run it on
  demand.
- **Topic settings:** 3 partitions each (messages keyed by `taskId`, so the
  events of one task stay ordered while three consumer instances could share
  the load), replication factor 1, `cleanup.policy=delete`,
  `retention.ms=604800000` (seven days). The bus is a transport, not the
  system of record: results are kept in the ledger (immudb) and task state
  in the saga database, so a week of history is enough for replay and
  debugging. Retention is the same for every topic and set by the script,
  not per row, until a topic needs otherwise.
- **Redpanda Console** `redpandadata/console:v3.12.0` on
  `127.0.0.1:8082`, with the Admin API enabled for broker details. It is
  bound to the loopback interface because it has no authentication. It
  joins `public` (it publishes a port, ADR-0003) and `services`. It starts
  after `redpanda-topics` completes successfully: Compose's `up --wait` does
  not wait for a one-shot job by itself, and this dependency makes
  `make up` return only once the topics exist.
- **Memory:** broker `mem_limit: 768m` (Seastar is given 512 MB, plus
  headroom for the process outside its allocator), Console `128m`, topic job
  `64m`. Measured on Docker Desktop (arm64) after producing and consuming
  20 000 messages: broker 154 MiB, Console 59 MiB. The broker limit is a
  deliberate deviation from the 256 MB database default of `CLAUDE.md` 6.2,
  commented in `compose/core.yml`; it is reviewed in the RAM audit (P11.2).
- **Licence:** Redpanda and Redpanda Console are free to use under the
  Business Source License (Community Edition). AaaS uses no Enterprise
  feature; the built-in evaluation period the Console reports does not
  affect the Community features, so the cost stays 0 PLN.

## Consequences

- `make up` (or `make up PROFILES=core`) leaves a healthy broker with the
  nine topics of `CLAUDE.md` 4.2 and the Console on <http://127.0.0.1:8082>.
- Services that produce or consume events depend on `redpanda-topics` with
  `condition: service_completed_successfully` and on `redpanda` with
  `condition: service_healthy`; they reach the broker as `redpanda:9092` on
  the `services` network.
- A new topic, or a `.v2` of an existing one, is one row in
  `contracts/events/topics.psv`; `make topics` creates it on a running
  broker. Removing a row does not delete the topic from the broker.
- A single broker loses no data across restarts (volume), but a removed
  volume (`make clean`) removes every event. This is recorded as R-010 in
  the risk register.
- Schemas are not enforced by the broker. Producers validate against
  `schema-registry` from P3.1 on.
