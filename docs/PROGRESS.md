# Progress

This file is the single source of truth about project progress. The
"Current State" block is read at the start of every working session; the
"Steps" table lists every step from `CLAUDE.md`, section 9.3, with its status.

Step statuses: `TODO`, `IN_PROGRESS`, `DONE`, `BLOCKED`. At most one step may be
`IN_PROGRESS` at any time.

## Current State

| Field | Value |
| --- | --- |
| Current phase | Phase 0 — Repository foundation |
| Last completed step | P0.5 — Pre-commit hooks |
| Last completed at | 2026-10-16 15:49 CEST |
| Snapshot tag | step/P0.5 |
| Step in progress | P0.6 — GitHub Actions CI |
| Next step | P0.6 — GitHub Actions CI |
| Blockers | none |
| Milestones reached | — |

## Steps

### Phase 0 — Repository foundation

| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P0.1 | Repository initialization: `.gitignore`, `.editorconfig`, `README.md`, `CLAUDE.md`, `docs/PROGRESS.md`, step log template, ADR-0001 | DONE | 2026-10-16 | step/P0.1 | [log](progress/steps/P0.1.md) |
| P0.2 | `Makefile`: `up`, `down`, `ps`, `logs`, `build`, `build-%`, `test`, `test-%`, `e2e`, `lint`, `fmt`, `new-service`, `clean`, `status` | DONE | 2026-10-16 | step/P0.2 | [log](progress/steps/P0.2.md) |
| P0.3 | Compose skeleton: `docker-compose.yml` with `include`, files in `compose/`, networks `public`/`services`/`data`, profiles, `.env.example` | DONE | 2026-10-16 | step/P0.3 | [log](progress/steps/P0.3.md) |
| P0.4 | Service template `templates/service/` and `scripts/new-service.sh <name> <language>` | DONE | 2026-10-16 | step/P0.4 | [log](progress/steps/P0.4.md) |
| P0.5 | Pre-commit: commitlint, hadolint, yamllint, shellcheck, line-ending check | DONE | 2026-10-16 | step/P0.5 | [log](progress/steps/P0.5.md) |
| P0.6 | GitHub Actions: lint, build of changed services (matrix per directory), tests, commitlint on PR | IN_PROGRESS | | | [log](progress/steps/P0.6.md) |
| P0.7 | Document templates in `templates/docs/` (all from CLAUDE.md 6.5.5), file header template per language, copied by `new-service.sh` | TODO | | | |
| P0.8 | Repository documents from CLAUDE.md 6.5.6: CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, CODEOWNERS, PR and issue templates, governance, ONBOARDING, GLOSSARY, first RISK_REGISTER entry | TODO | | | |
| P0.9 | `scripts/doc-check.sh` and `make doc-coverage`, run in CI | TODO | | | |
| P0.10 | MkDocs Material portal (`mkdocs.yml`, `make docs`, `make docs-serve`), git-cliff (`cliff.toml`), C4 context diagram | TODO | | | |

### Phase 1 — End-to-end skeleton (M1)

| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P1.1 | Redpanda + Redpanda Console in `compose/core.yml`, script creating the topics from CLAUDE.md 4.2 | TODO | | | |
| P1.2 | `gateway`: Traefik with file configuration, routing `/api` and `/` | TODO | | | |
| P1.3 | Event envelope and JSON Schema for `expression.submitted`, `addition.requested`, `result.voted`, `ledger.appended` in `contracts/events/` + example validation in CI | TODO | | | |
| P1.4 | `expression-assembler` (C#, SurrealDB): `POST /api/v1/keys`, expression assembly, event publishing, `202 {taskId}` | TODO | | | |
| P1.5 | `parser` (OCaml, SQLite): consumes `expression.submitted`, builds AST, publishes `addition.requested` (without validator and commutator) | TODO | | | |
| P1.6 | `successor` (Haskell, CouchDB): `Next(n) = n+1` computed natively, `TEMPORARY(P2.13)` | TODO | | | |
| P1.7 | `ledger` (Nim, immudb): consumes `addition.requested`, calls successor `b` times (`TEMPORARY(P3.3)`), stores result with hash, `GET /api/v1/tasks/{id}` (`TEMPORARY(P3.3)`) | TODO | | | |
| P1.8 | Temporary frontend: `frontend/shell` with one plain-JS page (keypad + display), `TEMPORARY(P8.x)` | TODO | | | |
| P1.9 | `tests/e2e` with the `2+3=5` case, `make e2e` — **M1** | TODO | | | |

### Phase 2 — Digits, carries, parsing (M2)

| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P2.1 | `contracts/proto/` + `buf.yaml`, `buf.gen.yaml`, code generation for Go, Rust, Haskell, OCaml, Elixir, C#, Crystal, Zig, Python; CI `buf lint` and `buf breaking` | TODO | | | |
| P2.2 | Digit contract `contracts/http/digit.yaml` + shared contract test for all digits (`tests/contract/digit.sh`) | TODO | | | |
| P2.3 | `digit-0` (C, SQLite) as the reference implementation | TODO | | | |
| P2.4 | `digit-1` (C++) | TODO | | | |
| P2.5 | `digit-2` (Fortran; HTTP wrapper allowed, ADR) | TODO | | | |
| P2.6 | `digit-3` (Free Pascal) | TODO | | | |
| P2.7 | `digit-4` (Lua) | TODO | | | |
| P2.8 | `digit-5` (Dart) | TODO | | | |
| P2.9 | `digit-6` (Swift) | TODO | | | |
| P2.10 | `digit-7` (Gleam) | TODO | | | |
| P2.11 | `digit-8` (D) | TODO | | | |
| P2.12 | `digit-9` (Racket), `next = 0`, `carry = true` | TODO | | | |
| P2.13 | `carry` (Elixir, Mnesia) + `successor` computes n+1 through digit services and carry; remove `TEMPORARY(P2.13)` | TODO | | | |
| P2.14 | `validator` (Rust, MariaDB): range 0–99 999 | TODO | | | |
| P2.15 | `commutator` (Zig, LMDB): a ≥ b | TODO | | | |
| P2.16 | `operator-registry` (Crystal, PostgreSQL): `+` → `addition` | TODO | | | |
| P2.17 | `parser` calls validator, commutator, operator-registry | TODO | | | |
| P2.18 | E2E: `0+0`, `9+1`, `99+1`, `99999+1`, `3+5 == 5+3`, out-of-range values → error — **M2** | TODO | | | |

### Phase 3 — Saga and reliability (M3)

| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P3.1 | `schema-registry` (Apicurio, PostgreSQL): registration of all schemas from `contracts/events/` at startup, producers validate before publishing | TODO | | | |
| P3.2 | Temporal server + UI + PostgreSQL in `compose/core.yml` | TODO | | | |
| P3.3 | `saga-orchestrator` (Go): `AdditionWorkflow`, activities `resolveDigits`, `successor`, continue-as-new every 1000, progress Query, `GET /api/v1/tasks/{id}`; remove `TEMPORARY(P3.3)` from ledger | TODO | | | |
| P3.4 | Outbox in `saga_db` + `outbox-relay` (Debezium, outbox event router) publishes `result.voted`; ledger consumes `result.voted` instead of `addition.requested` | TODO | | | |
| P3.5 | `distributed-lock` (etcd) + ledger takes the `ledger-append` lock | TODO | | | |
| P3.6 | `dead-letter` (Perl, MongoDB): `aaas.dlq.v1`, backoff, max 5 attempts, `compensate` signal to the saga; all consumers send to DLQ | TODO | | | |
| P3.7 | `ledger`: `GET /api/v1/ledger/verify`, test with a tampered entry | TODO | | | |
| P3.8 | `tests/chaos`: kill `successor`, `carry` and `digit-5` during 500+500, result still 1000 — **M3** | TODO | | | |

### Phase 4 — Consensus (M4)

| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P4.1 | `consensus` (Go + hashicorp/raft, BoltDB): 3 nodes, `Vote` API | TODO | | | |
| P4.2 | Python replica | TODO | | | |
| P4.3 | Rust replica | TODO | | | |
| P4.4 | COBOL replica (GnuCOBOL; wrapper allowed, ADR) | TODO | | | |
| P4.5 | Saga calls `vote`; mismatch with Peano → DLQ and `FAILED` | TODO | | | |
| P4.6 | Fault injection (`FAULT_INJECT=off-by-one` in one replica): majority wins; two faulty → `FAILED` — **M4** | TODO | | | |

### Phase 5 — Platform

| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P5.1 | `service-discovery` (Consul) + registration of all existing services (bootstrap library per language or sidecar, ADR) | TODO | | | |
| P5.2 | `config-server` (PHP, MongoDB) + `AAAS_BOOTSTRAP=platform` in services | TODO | | | |
| P5.3 | `secrets` (OpenBao): AppRole per service, database passwords moved out of `.env` | TODO | | | |
| P5.4 | `gateway` switches to the Redis provider (routes in Redis, seeded at startup) | TODO | | | |

### Phase 6 — Security and edge (M5)

| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P6.1 | `auth` (Keycloak, PostgreSQL): realm `aaas`, client `frontend`, guest login, realm export to `infra/keycloak/` | TODO | | | |
| P6.2 | `rate-limiter` (Ruby, Redis): forwardAuth in Traefik, JWT verification (JWKS), limits from CLAUDE.md section 3 | TODO | | | |
| P6.3 | `idempotency` (Deno, Valkey): `Claim`/`MarkFailed`, used by expression-assembler | TODO | | | |
| P6.4 | `feature-flags` (Unleash, PostgreSQL): `addition_enabled` flag, checked by operator-registry | TODO | | | |
| P6.5 | Frontend: login flow, token in requests; E2E with guest login — **M5** | TODO | | | |

### Phase 7 — Observability

| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P7.1 | OTel Collector, Prometheus, Loki, Jaeger, Grafana with provisioning (`compose/observability.yml`) | TODO | | | |
| P7.2 | Instrumentation of all services: traces through HTTP, gRPC and events | TODO | | | |
| P7.3 | Dashboards: "Life of one addition", "Successor/s", per service (RAM, errors, latency) | TODO | | | |
| P7.4 | Alertmanager: service down, DLQ growing, task > 40 min, host RAM > 90% | TODO | | | |

### Phase 8 — Microfrontends (M6)

| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P8.1 | `frontend/shell` (single-spa): import map, calculator layout, `aaas:*` bus, login from P6.5 | TODO | | | |
| P8.2 | `frontend/display` (Elm): expression, status, result, polling `/tasks/{id}` | TODO | | | |
| P8.3 | `frontend/key-0` (React) | TODO | | | |
| P8.4 | `frontend/key-1` (Vue) | TODO | | | |
| P8.5 | `frontend/key-2` (Svelte) | TODO | | | |
| P8.6 | `frontend/key-3` (Angular) | TODO | | | |
| P8.7 | `frontend/key-4` (SolidJS) | TODO | | | |
| P8.8 | `frontend/key-5` (Preact) | TODO | | | |
| P8.9 | `frontend/key-6` (Lit) | TODO | | | |
| P8.10 | `frontend/key-7` (Qwik) | TODO | | | |
| P8.11 | `frontend/key-8` (Alpine.js) | TODO | | | |
| P8.12 | `frontend/key-9` (Ember) | TODO | | | |
| P8.13 | `frontend/key-plus` (htmx) | TODO | | | |
| P8.14 | `frontend/key-equals` (Mithril): generates `Idempotency-Key` | TODO | | | |
| P8.15 | `frontend/key-clear` (plain JS); remove the temporary frontend from P1.8 | TODO | | | |
| P8.16 | `stopwatch` (Kotlin/Ktor, TimescaleDB): start/stop from events, SSE | TODO | | | |
| P8.17 | `frontend/timer` (Marko): timer fed by SSE — **M6** | TODO | | | |

### Phase 9 — Invoices

| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P9.1 | `billing` (Common Lisp/SBCL, Firebird): consumes `ledger.appended`, numbering under the `invoice-number` lock, idempotent | TODO | | | |
| P9.2 | Typst template: fictional seller without tax ID, amount 0.00 PLN, clear "humorous document, not a VAT invoice" note, `GET /api/v1/invoices/{taskId}.pdf` | TODO | | | |
| P9.3 | `frontend/invoice-button` (Stencil) | TODO | | | |

### Phase 10 — AWS (M7)

| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P10.1 | Floci in the `aws-local` profile, `AWS_ENDPOINT_URL` variable in services | TODO | | | |
| P10.2 | `infra/aws/` (OpenTofu): SQS, Lambda (outside VPC, reserved concurrency 1), DynamoDB (on-demand), minimal IAM, CloudWatch retention 1 day, AWS Budgets alert at 1 USD; `tofu apply` targets Floci by default | TODO | | | |
| P10.3 | `cloud-notary` (Python Lambda): chain verification, DynamoDB write, tests on Floci | TODO | | | |
| P10.4 | `ledger` sends the entry to SQS after the write (endpoint from configuration) | TODO | | | |
| P10.5 | Deployment to the real AWS account **only with the user's explicit consent**: checklist from CLAUDE.md section 10 — **M7** | TODO | | | |

### Phase 11 — Hardening

| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P11.1 | k6: measurement of successor call time, update of the timing table in CLAUDE.md and README | TODO | | | |
| P11.2 | RAM audit: per-container usage table in `docs/architecture.md`, `mem_limit` corrections | TODO | | | |
| P11.3 | `docs/architecture.md`: Mermaid diagrams (flow, networks, events), links to dashboards | TODO | | | |
| P11.4 | Documentation audit: 100% coverage in all services, complete document sets, C4 container and component diagrams, event and API catalogs in the portal, RISK_REGISTER and DPIA review | TODO | | | |
| P11.5 | Removal of all `TEMPORARY` markers, ADR review, project-wide release notes, `phase-11-done` | TODO | | | |

### Phase 12 — Public access (DEFERRED)

Not started until the user explicitly asks for it. See `CLAUDE.md`, section 9.3.
