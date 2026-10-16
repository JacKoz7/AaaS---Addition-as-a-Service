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
make up      # starts everything except the aws-local profile
make e2e     # proves that 2 + 3 = 5
make down
```

Requirements: Docker with Compose, `make`, 16 GB RAM minimum (32 GB recommended).
The `Makefile` arrives in step P0.2; until then, there is nothing to run.

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
| `services/<service>/` | One directory per microservice (from Phase 1) |
| `frontend/<element>/` | One directory per microfrontend (from Phase 1) |
| `contracts/` | JSON Schemas, Protobuf and OpenAPI contracts (from Phase 1) |
| `compose/` | Docker Compose files (from step P0.3) |

## Cost

0.00 PLN. Only open-source software is used. The single cloud component runs
within the AWS Always Free limits (Lambda, SQS, DynamoDB) and is emulated
locally with Floci by default.

## License

MIT. See [`LICENSE`](LICENSE).
