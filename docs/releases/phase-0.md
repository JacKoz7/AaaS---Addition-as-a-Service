# Release Notes — Phase 0: Repository Foundation

| Field | Value |
| --- | --- |
| Document | Phase Release Notes |
| Phase | 0 — Repository foundation |
| Date | 2026-10-16 |
| Status | Released |
| Milestone | None (the first milestone, M1, follows Phase 1) |
| Tag | `phase-0-done` |
| Steps | P0.1 – P0.10 |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |

## Announcement

We are thrilled to announce the completion of Phase 0 of AaaS — Addition as a
Service. In a single, focused delivery day, the Platform Enablement Guild has
laid the governance, tooling and documentation foundation on which 35
microservices will compute the sum of two integers.

Not a single integer has been added yet. That is by design: before the first
`+`, every future contributor can now scaffold a service in one command,
have every commit checked, and find every decision in one portal.

## What Is Included

| Step | Delivered |
| --- | --- |
| P0.1 | Repository initialization: `.gitignore`, `.editorconfig`, `README.md`, `CLAUDE.md`, progress tracking (`docs/PROGRESS.md`, step logs), ADR-0001 |
| P0.2 | Root `Makefile`: `up`, `down`, `ps`, `logs`, `build`, `test`, `e2e`, `lint`, `fmt`, `new-service`, `clean`, `status`, per-component delegation (ADR-0002) |
| P0.3 | Compose skeleton: `docker-compose.yml` with `include`, `compose/*.yml`, networks `public`/`services`/`data`, profiles, `.env.example` (ADR-0003) |
| P0.4 | Service template and `scripts/new-service.sh` with `TODO(scaffold)` markers (ADR-0004) |
| P0.5 | Pre-commit hooks: commitlint with the `Step:` trailer, hadolint, yamllint, shellcheck, line endings (ADR-0005) |
| P0.6 | GitHub Actions: repository lint, commitlint, matrix build/lint/test of changed components (ADR-0006) |
| P0.7 | Templates of the ten service documents and of the file header in every language (ADR-0007) |
| P0.8 | Repository documents: CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, CODEOWNERS, PR and issue templates, governance, onboarding, glossary, risk register (ADR-0008) |
| P0.9 | `scripts/doc-check.sh` and `make doc-coverage`: headers and documented definitions at 100%, in pre-commit and CI (ADR-0009) |
| P0.10 | Documentation portal (`make docs`, `make docs-serve`) with service map and catalogs, native API docs export, git-cliff changelogs, C4 system context (ADR-0010) |

## Business Impact

Phase 0 converts an idea into an operable delivery organisation: every step
leaves a snapshot tag and a log, every architectural decision has an ADR,
and the documentation standard of `CLAUDE.md` 6.5 is enforced by machines
rather than goodwill. The addition capability itself remains at zero sums
per second; Phase 1 will deliver `2 + 3 = 5` through the gateway (M1).

## Known Limitations

- No service exists yet; `make up`, `make build` and `make test` have
  nothing to run, and `make e2e` arrives in P1.9.
- The C4 container and component diagrams are scheduled for P11.4.

## What Comes Next

Phase 1 — End-to-end skeleton: Redpanda, the gateway, the first event
contracts, `expression-assembler`, `parser`, `successor`, `ledger`, a
temporary frontend and the first end-to-end test.
