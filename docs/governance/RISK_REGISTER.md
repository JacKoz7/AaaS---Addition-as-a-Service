# Risk Register

| Field | Value |
| --- | --- |
| Document | Enterprise Risk Register |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Last Reviewed | 2026-10-16 |
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

## Closed Risks

None.
