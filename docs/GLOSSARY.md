# Glossary

| Field | Value |
| --- | --- |
| Document | Glossary of Terms |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Last Reviewed | 2026-10-16 |

Extension of `CLAUDE.md` section 11. Terms are in alphabetical order.

| Term | Meaning |
| --- | --- |
| ADR | Architecture Decision Record: a short document of one decision (context, decision, consequences) in `docs/adr/NNNN-title.md`. |
| AEC, CGC, CXT, OSG, PEG, ROU, TIB, TIO | The eight teams of `CLAUDE.md` 6.5.1: Arithmetic Excellence Center, Cloud Governance Committee, Customer Experience Tribe, Observability Steering Group, Platform Enablement Guild, Revenue Operations Unit, Trust & Identity Board, Transaction Integrity Office. |
| AppRole | OpenBao authentication method: each service logs in with its own `role_id`/`secret_id` to read its database password (P5.3). |
| AST | Abstract syntax tree of the expression, built by `parser`. |
| Bootstrap mode | `AAAS_BOOTSTRAP=env` (configuration from environment variables) or `platform` (config-server, OpenBao, Consul, schema-registry). |
| C4 model | Notation for architecture diagrams at four levels (system context, containers, components, code); AaaS draws them in Mermaid in `docs/architecture/c4/` (ADR-0010). |
| Carry | Transfer of one unit to the next higher digit position when a digit wraps from 9 to 0; performed by the `carry` service. |
| CDC | Change Data Capture: reading database changes from the transaction log; Debezium uses it to publish the outbox. |
| Checkpoint | Commit `chore(progress): checkpoint ...` on a step branch that saves unfinished work, with "Next actions" in the step log. |
| Commutator | Service that swaps `a` and `b` so that `b` is the smaller operand, minimising successor calls. |
| Component | A service (`services/<name>`) or microfrontend (`frontend/<element>`) with its own Makefile; the unit of the CI matrix. |
| Compose profile | Group of containers started together: `core`, `services`, `frontend`, `observability`, `aws-local`. |
| Consensus | Three replicas (Python, Rust, COBOL) compute `a + b` natively and Raft commits the majority result, which must equal the Peano result. |
| Continue-as-new | Temporal mechanism restarting a workflow with a fresh history; the addition workflow uses it every 1000 iterations. |
| Contract | Machine-readable interface: JSON Schema of an event, `.proto` of a gRPC service, OpenAPI of an HTTP API, in `contracts/`. |
| Definition of Done | Checklist every step must satisfy before it is closed (`CLAUDE.md` 9.1). |
| Digit service | One of `digit-0` to `digit-9`: returns its value and its successor digit from its own SQLite database. |
| DLQ | Dead Letter Queue: topic `aaas.dlq.v1` for events that failed after local retries; handled by `dead-letter`. |
| Documentation portal | MkDocs Material site assembled from every document of the repository plus generated catalogs; `make docs` builds it into `docs/site/`, `make docs-serve` serves it (ADR-0010). |
| DPIA | Data Protection Impact Assessment under GDPR, in `docs/governance/DPIA.md`. |
| Event envelope | Common JSON wrapper of every event: `eventId`, `type`, `version`, `occurredAt`, `producer`, `taskId`, `traceparent`, `payload`. |
| Floci | Local emulator of AWS services, the default target of the infrastructure code. |
| forwardAuth | Traefik middleware that asks an external service (`rate-limiter`) whether to let a request through. |
| git-cliff | Changelog generator that renders Conventional Commits through a template (`cliff.toml`); used by `make changelog-<component>` (ADR-0010). |
| Hash chain | `hash = sha256(prevHash || taskId || a || b || result || timestamp)`; any modification breaks every later hash. |
| Idempotency key | Header `Idempotency-Key` of the `=` request; the same key always maps to the same task. |
| Ledger | Immutable record of results in immudb, each entry hashed together with the previous hash. |
| Microfrontend | Independently built and served part of the UI (each key, the display, the timer, the invoice button), composed by the single-spa shell. |
| Milestone | M1 to M7: a working capability at the end of a phase (`CLAUDE.md` 9.2). |
| Outbox | Pattern: the event is written in the same database transaction as the data and published afterwards by CDC. |
| Partition | Ordered subset of a topic; AaaS keys messages by `taskId`, so all events of one task land in the same partition in order. |
| Peano arithmetic | Addition as repeated successor: `a + b = S(S(...S(a)))`, `b` times. |
| Phase | Group of steps ending in a milestone; tagged `phase-N-done`. |
| RACI | Responsible, Accountable, Consulted, Informed: assignment of roles per activity in each service's `RACI.md`. |
| Raft | Consensus algorithm used by the consensus service (hashicorp/raft), Consul, OpenBao and etcd. |
| Redpanda | Kafka-API-compatible event bus of AaaS: one broker in the `core` profile, with Redpanda Console on port 8082 (ADR-0011). |
| RFC | Request for Comments: proposal for a change spanning several services, in `docs/rfc/` (`docs/governance/RFC_PROCESS.md`). |
| Saga | Long-running transaction split into steps with compensation on failure; here the Temporal `AdditionWorkflow`. |
| Scaffold | Directory generated by `scripts/new-service.sh`; incomplete until every `TODO(scaffold)` marker is replaced. |
| SLI, SLO, error budget | Indicator measured, objective set for it, and the tolerated failure share within the window (`SLO.md` of each service). |
| Snapshot tag | Git tag `step/P<phase>.<step>` marking the repository state after a step. |
| Step | Item of the plan in `CLAUDE.md` 9.3, identified as `P<phase>.<step>`, with a log in `docs/progress/steps/`. |
| STRIDE | Threat categories: Spoofing, Tampering, Repudiation, Information disclosure, Denial of service, Elevation of privilege. |
| Successor | `S(n) = n + 1`, computed by the `successor` service through the digit services and `carry`. |
| Task | One addition, identified by `taskId` (UUIDv7), with statuses `ACCEPTED`, `PARSED`, `COUNTING`, `VOTING`, `RECORDING`, `RECORDED` or `FAILED`. |
| TEMPORARY marker | Comment `TEMPORARY(P<phase>.<step>): ...` marking a shortcut removed by the named step; listed by `make lint`. |
| Topic registry | `contracts/events/topics.psv`: every Redpanda topic with partitions, producer and consumers; creates the topics (`make topics`) and feeds the event catalog (ADR-0011). |
| traceparent | W3C Trace Context header (and envelope field) propagating one trace across HTTP, gRPC and events. |
