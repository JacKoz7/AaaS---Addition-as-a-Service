# Risk Register

| Field | Value |
| --- | --- |
| Document | Enterprise Risk Register |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Last Reviewed | 2026-10-17 |
| Review Cadence | At the end of every phase, and whenever an incident or RFC adds a risk |

## Scales

| Score | Likelihood | Impact |
| --- | --- | --- |
| 1 | Rare: not expected during the project | Negligible: cosmetic, no addition affected |
| 2 | Unlikely | Minor: an addition is delayed |
| 3 | Possible | Moderate: additions fail, data intact |
| 4 | Likely | Major: system cannot run on the target host, or cost incurred |
| 5 | Almost certain | Severe: a wrong result is recorded, or uncontrolled cost |

**Rating** = Likelihood x Impact: 1–4 Low, 5–9 Medium, 10–16 High, 20–25 Critical.

## Register

| ID | Risk | Likelihood | Impact | Rating | Owner | Mitigation | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R-001 | 35 services, their databases, Temporal, Redpanda and the observability stack exceed the memory of a 16 GB host | 4 | 4 | 16 High | PEG | `mem_limit` on every container with class defaults (`CLAUDE.md` 6.2); measured usage in each `CAPACITY.md` after every new service (`CLAUDE.md` 8.10); RAM audit in P11.2 | Open |
| R-002 | A mandated language lacks an HTTP/gRPC library or a `linux/arm64` image (Fortran, Free Pascal, Racket, Lua, COBOL) | 4 | 3 | 12 High | AEC | Allowed thin wrappers (CGI, `socat`) with logic in the target language, each recorded in an ADR (`CLAUDE.md` 4.4, 8.6); language never changed without the owner's consent | Open |
| R-003 | Resources created in a real AWS account incur cost | 2 | 5 | 10 High | CGC | Floci is the default target; real AWS only with explicit consent in the current session (`CLAUDE.md` 8.8, 10); Always Free services only; reserved concurrency 1; AWS Budgets alert at 1 USD | Open |
| R-004 | A wrong sum is recorded because a digit, successor or carry service is defective | 2 | 5 | 10 High | TIO | Three independent consensus replicas vote against the Peano result (P4.5); mismatch goes to DLQ and `FAILED`; E2E cases for carry chains (P2.18); fault injection test (P4.6) | Open |
| R-005 | Large additions exceed the Temporal history limit and fail | 3 | 3 | 9 Medium | TIO | `continue-as-new` every 1000 iterations (`CLAUDE.md` 3, step 7); E2E with 99999 + 1 | Open |
| R-006 | Single maintainer: knowledge is lost between sessions | 3 | 3 | 9 Medium | PEG | Repository is the only source of truth for progress (`CLAUDE.md` 8.1): step logs, snapshot tags, checkpoints, ADRs, onboarding guide | Open |
| R-007 | A compromised or changed third-party image or action alters the build | 2 | 4 | 8 Medium | TIB | Base images pinned to versions (no `latest`, hadolint DL3006/DL3007 as errors); GitHub Actions pinned to commit SHAs (ADR-0006) | Open |
| R-008 | The joke invoice is mistaken for a real tax document | 1 | 3 | 3 Low | ROU | Amount 0.00 PLN, fictitious seller without a tax ID, explicit notice that it is not a VAT invoice (P9.2) | Open |
| R-009 | MkDocs 2.0 removes the plugin and hook system and is announced as incompatible with Material for MkDocs; an unpinned upgrade breaks the portal | 2 | 2 | 4 Low | PEG | MkDocs 1.6.1 and Material 9.7.7 pinned in the tool image `infra/docs-portal/Dockerfile`; the portal logic lives in one hook (`scripts/docs-portal.py`) that produces plain Markdown, so a move to another generator reuses it (ADR-0010) | Open |
| R-010 | The single Redpanda broker has no replica; removing its volume (`make clean`) or a disk fault loses every event not yet consumed | 2 | 2 | 4 Low | PEG | Events are transport, not the system of record: results live in the ledger (immudb), task state in the saga database; topics are recreated from `contracts/events/topics.psv`; consumers are idempotent by `eventId` (`CLAUDE.md` 4.2, ADR-0011) | Open |
| R-011 | An incompatible change is made inside an existing event schema (a new required field, a narrowed type) and breaks producers or consumers that rely on the old contract | 2 | 3 | 6 Medium | PEG | Compatibility policy of ADR-0013 (only optional fields may be added within a version; everything else is a new `.v<N+1>` topic); separate `contract(contracts)` commits reviewed by the owning team; `make contracts-check` in CI; compatibility rules enforced by `schema-registry` from P3.1 | Open |
| R-012 | Stored key presses and tasks of `expression-assembler` (about 4 KB per press) and processed events of `parser` (about 1 KB per expression) grow without a retention job and eventually fill the host disk | 1 | 2 | 2 Low | CXT, AEC | Each addition costs at most 12 presses and one parsed expression; per-user limits from P6.2 (120 presses per minute); usage visible in `docker system df`; `make clean` erases the data; a retention job is to be decided when public access (Phase 12) is planned | Open |
| R-013 | A second `parser` instance is started (for example `docker compose up --scale parser=2`): the OCaml Kafka bindings have no group-balanced consumer, so both instances consume every partition into separate databases and request each addition twice with different `eventId`s | 1 | 3 | 3 Low | AEC | Single instance by design and documented (ADR-0015, parser RUNBOOK 2.6); Compose defines one replica; downstream consumers key the work by `taskId` (the saga's workflow ID from P3.3); scaling out requires a group-balanced consumer first | Open |
| R-014 | The successor writes one CouchDB document (about 3.2 KB on disk before compaction) and one event per step of every addition: 99 999 + 99 999 alone adds about 320 MB to the call log and 99 999 messages to `aaas.successor.called.v1`; without a retention job the host disk fills | 2 | 2 | 4 Low | AEC | Topic retention of Redpanda (ADR-0011) bounds the events; the call log is visible in `docker system df -v` and erased by `make clean`; per-user addition limits from P6.2; a compaction or retention job is to be decided before public access (Phase 12) | Open |
| R-015 | immudb never deletes data: every ledger entry, consumed event and task is kept, and every checkpoint adds a version of its task row (one per 1 000 successor calls); the `ledger-data` volume grows for the lifetime of the system | 2 | 1 | 2 Low | TIO | Growth is small by design: 972 KB for the `ledger` database after 15 additions, at most 100 checkpoint versions per addition (services/ledger/docs/CAPACITY.md); the ledger is the record of results and is not pruned on purpose; visible in `docker system df -v`, erased by `make clean` | Open |
| R-016 | immudb 1.11.2 is under the Business Source License 1.1, not an OSI licence: production use is granted free of charge only outside a competing paid offering, and the terms could change for later releases | 1 | 2 | 2 Low | TIO | AaaS uses immudb free of charge and offers nothing commercial, which `CLAUDE.md` 1, rule 3 allows (ADR-0017); each release becomes Apache-2.0 four years after publication; the last Apache-2.0 image (1.9DOM.1) lacks linux/arm64; the version is pinned and reviewed before any upgrade | Open |

## Closed Risks

None.
