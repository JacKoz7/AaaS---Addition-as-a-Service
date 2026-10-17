# Onboarding: Your First Day at AaaS

| Field | Value |
| --- | --- |
| Document | New Team Member Onboarding |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Last Reviewed | 2026-10-16 |

Welcome to Addition as a Service. By the end of this guide you will have the
repository on your machine, the tooling working, and you will know where the
project stands. Once milestone M1 is reached you will also have computed
`2 + 3 = 5` through the full system.

## 1. Understand the Mission (15 minutes)

AaaS adds two non-negative integers from 0 to 99 999. It does so with 35
microservices in 28 languages, Peano arithmetic, a saga, a consensus vote, a
hash-chained ledger and a 0.00 PLN invoice. The complexity is intentional;
every element has a role in computing the sum or in making sure it is right.

Read, in this order:

1. [`README.md`](../../README.md) — overview and repository map.
2. [`CLAUDE.md`](../../CLAUDE.md) — the specification (in Polish): sections 1
   (principles), 3 (the flow of `2 + 3`), 6 (conventions) and 9 (the plan).
3. [`GLOSSARY.md`](../GLOSSARY.md) — the vocabulary.
4. [`docs/adr/`](../adr/) — the decisions taken so far.

Prefer reading online? `make docs-serve` serves all of the above, plus the
service map and the catalogs, at <http://127.0.0.1:8000> (ADR-0010; use
`make docs-serve DOCS_PORT=<port>` if 8000 is taken).

## 2. Prepare Your Workstation (30 minutes)

| Requirement | Why | Check |
| --- | --- | --- |
| 16 GB RAM (32 GB recommended) | All services run locally | — |
| Docker Desktop (or Docker Engine) with Compose v2 | Everything builds and runs in containers | `docker compose version` |
| Git | Version control | `git --version` |
| GNU Make or BSD make | Entry point to every command | `make --version` |
| pre-commit | Git hooks | `pre-commit --version` |
| GitHub CLI (optional) | CI status, pull requests | `gh --version` |

No language toolchain is installed on the host: every component is built,
linted and tested inside Docker (ADR-0002).

## 3. Clone and Install the Hooks (10 minutes)

Clone into a directory that no file-sync service manages. On macOS,
`~/Desktop` and `~/Documents` are synchronised by iCloud Drive when "Desktop
& Documents Folders" is enabled; iCloud replaces files under git's feet,
creating copies such as `Makefile 2` and restoring stale versions (this
happened during P0.9). `~/Developer` is not synchronised.

```sh
mkdir -p ~/Developer && cd ~/Developer
git clone git@github.com:JacKoz7/AaaS---Addition-as-a-Service.git AaaS
cd AaaS
cp .env.example .env
pre-commit install --install-hooks   # needs Docker running; takes about a minute
make help
```

Pushing workflow files over HTTPS requires a token with the `workflow`
scope; cloning over SSH avoids that (see the P0.6 step log).

## 4. Find Out Where the Project Stands (10 minutes)

```sh
make status
```

It prints the "Current State" block of
[`docs/PROGRESS.md`](../PROGRESS.md), the step in progress, the latest
snapshot tags and the containers. The log of every completed step is in
[`docs/progress/steps/`](../progress/steps/).

## 5. Run the System

```sh
make up      # starts every profile except aws-local and waits for healthchecks
make ps
make down
```

Current state (Phase 1): `make up` starts the Redpanda event bus, creates its
topics and serves Redpanda Console on <http://127.0.0.1:8082>;
`make topics-check` confirms the topics. The gateway answers on
<http://127.0.0.1/> and forwards `POST /api/v1/keys` to `expression-assembler`
(key presses, `=` returns a `taskId`; example in
[its README](../../services/expression-assembler/README.md)); the other
routes return `502 Bad Gateway` until their services arrive in the next
steps.

From milestone **M1** (step P1.9): open <http://localhost/>, press `2`, `+`,
`3`, `=` and wait for the display to show `5`. `make e2e` runs the same
scenario automatically.

## 6. Make Your First Change

1. Pick the "Next step" from `make status`.
2. Follow [`CONTRIBUTING.md`](../../CONTRIBUTING.md): step branch, start
   commit, work, close the step.
3. A new service starts with `make new-service NAME=<name> LANG=<language>`;
   every file starts with a header from `scripts/file-header.sh render`.
4. An event contract changes in `contracts/events/` (schema plus valid and
   invalid examples, ADR-0013) in its own `contract(contracts)` commit;
   `make contracts-check` validates it.

## 7. Who Owns What

Teams are listed in `CLAUDE.md` 6.5.1 and mapped to directories in
[`CODEOWNERS`](../../CODEOWNERS). Every team is represented by the
repository owner.
