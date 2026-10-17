# AaaS — Addition as a Service

> **Enterprise-grade addition of two non-negative integers.**
> 35 microservices, 28 programming languages, one `+`.

AaaS adds two integers in the range 0–99 999 and nothing else. The user sees a
calculator keypad, a display, a waiting-time counter and a button that downloads
an invoice for 0.00 PLN. Behind that keypad sits a deliberately exaggerated but
logically coherent distributed system: every service has a role in computing
the sum or in making sure the computation succeeds.

## Why

Because `a + b` is too simple to be trusted. AaaS computes addition with Peano
arithmetic (`a + b` is `b` calls of the `successor` service), confirms the result
by a three-replica Raft consensus, records it in an immutable hash-chained
ledger, notarizes it in the cloud and issues an invoice. Every step is
documented as if the company's revenue depended on it. The revenue is 0.00 PLN.

## What it looks like

| Example | Successor calls | Estimated time |
| --- | --- | --- |
| 2 + 3 | 2 | 1–3 s |
| 1 000 + 1 000 | 1 000 | 10–25 s |
| 50 000 + 70 000 | 50 000 | 8–17 min |
| 99 999 + 99 999 | 99 999 | 17–35 min |

The waiting time is a feature. Real timings will be measured in Phase 11.

## Architecture in one paragraph

Key presses go through the `gateway` (Traefik) to the `expression-assembler`.
On `=`, an event is published to Redpanda. The `parser` builds an AST and asks
the `validator`, the `commutator` and the `operator-registry` whether the
addition may proceed. The `saga-orchestrator` (Temporal) then calls `successor`
`b` times; `successor` increments digits by asking ten `digit-N` services and
the `carry` service. The `consensus` cluster votes on the result, the `ledger`
appends it to a hash chain, the `stopwatch` stops the clock, `billing` issues
the invoice and the `cloud-notary` (AWS Lambda) verifies the chain. The full
service catalog, contracts and request flow are described in [`CLAUDE.md`](CLAUDE.md).

## Running it

```sh
make help    # lists every target
make status  # current step, latest snapshots, container state
make new-service NAME=successor LANG=haskell   # scaffold a service
make up      # starts everything except the aws-local profile
make topics-check   # Redpanda topics match contracts/events/topics.psv
make contracts-check   # event schemas and their examples (also run by make lint)
make e2e     # proves that 2 + 3 = 5
make down
```

Requirements: Docker with Compose, `make`, 16 GB RAM minimum (32 GB recommended).
Targets whose inputs arrive in a later step (for example `make up` before the
Compose skeleton of step P0.3) fail with a message naming that step.

## Contributing

Start with [`docs/onboarding/ONBOARDING.md`](docs/onboarding/ONBOARDING.md) and
[`CONTRIBUTING.md`](CONTRIBUTING.md). Participation is governed by the
[Code of Conduct](CODE_OF_CONDUCT.md); vulnerabilities are reported as described
in [`SECURITY.md`](SECURITY.md).

Install the git hooks once after cloning:

```sh
brew install pre-commit        # or: pip install pre-commit
pre-commit install --install-hooks
```

The hooks enforce LF line endings, lint YAML, shell scripts and Dockerfiles,
and check every commit message against Conventional Commits with the mandatory
`Step: P<phase>.<step>` trailer (see `CLAUDE.md`, section 7.1). `make lint`
runs the same checks on all files. `make doc-coverage` verifies that every
file has the mandatory header and every definition is documented
(ADR-0009).

GitHub Actions (`.github/workflows/ci.yml`, see ADR-0006) runs the same hooks,
lints every commit message of the push or pull request, and builds, lints and
unit-tests each changed service or microfrontend in its own matrix job.

## Documentation portal

```sh
make docs        # builds the MkDocs Material portal into docs/site (strict)
make docs-serve  # serves it on http://127.0.0.1:8000 with live rebuild
```

The portal collects every document of the repository, the service map and
the service, event, API and changelog catalogs (ADR-0010). Component
changelogs are generated from commits with `make changelog-<component>`.

## Project status

Progress is tracked in [`docs/PROGRESS.md`](docs/PROGRESS.md). Each completed
step is tagged `step/P<phase>.<step>` and has a log in
[`docs/progress/steps/`](docs/progress/steps/). Architecture decisions live in
[`docs/adr/`](docs/adr/).

## Repository map

| Path | Content |
| --- | --- |
| `CLAUDE.md` | Specification, conventions and the step-by-step plan (in Polish) |
| `docs/PROGRESS.md` | Current state and the checklist of every step |
| `docs/progress/steps/` | One log per step |
| `docs/adr/` | Architecture Decision Records |
| `docs/rfc/` | Requests for Comments for cross-service changes (`TEMPLATE.md`) |
| `docs/governance/` | RFC process, risk register, DPIA, release process, postmortem template |
| `docs/onboarding/` | First-day guide |
| `docs/GLOSSARY.md` | Glossary of terms |
| `CODEOWNERS` | Directory-to-team mapping (ADR-0008) |
| `.github/` | CI workflow, pull request and issue templates |
| `Makefile` | Entry point: `make help` |
| `services/<service>/` | One directory per microservice (from Phase 1) |
| `frontend/<element>/` | One directory per microfrontend (from Phase 1) |
| `contracts/` | Contracts: topic registry `events/topics.psv`; JSON Schemas, Protobuf and OpenAPI from later Phase 1 and 2 steps |
| `compose/` | Docker Compose files, one per profile (see `compose/README.md`) |
| `infra/` | Configuration of shared infrastructure and tools: `redpanda/` (topic job, ADR-0011), `docs-portal/` (portal tool image, ADR-0010) |
| `templates/service/` | Language-agnostic service template and service catalog (`catalog.psv`) rendered by `scripts/new-service.sh` |
| `templates/docs/` | Templates of the ten documents every service carries (`CLAUDE.md` 6.5.5) |
| `templates/headers/` | Mandatory file header per file type; render with `scripts/file-header.sh` |
| `scripts/` | Repository scripts (`new-service.sh`, `file-header.sh`, `doc-check.sh`, later `e2e.sh`) |
| `scripts/lib/` | Shared shell functions and data of the scripts (header styles, definition patterns) |
| `scripts/ci/` | CI helpers (`changed-components.sh`: matrix of changed components) |
| `.github/workflows/` | GitHub Actions CI (`ci.yml`) |
| `docker-compose.yml` | Root Compose file: project name, networks, includes |

## Cost

0.00 PLN. Only open-source software is used. The single cloud component runs
within the AWS Always Free limits (Lambda, SQS, DynamoDB) and is emulated
locally with Floci by default.

## License

MIT. See [`LICENSE`](LICENSE).
