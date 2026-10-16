# ADR-0002: Per-component Makefile delegation

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-16 |
| Deciders | Platform Enablement Guild (PEG) |
| Step | P0.2 |

## Context

`CLAUDE.md` requires a single set of commands (`make test-<service>`,
`make lint`, `make fmt`) that works across 28 languages and 17 frontend
frameworks, each with its own test runner, formatter and linter. Encoding
every language's toolchain in the root `Makefile` would make it a thousand-line
switch statement that changes with every new service.

Building, by contrast, is uniform: every component is a Docker image defined
in Compose, and the image Compose runs must be the image that was built.

## Decision

- `make build` and `make build-<name>` run `docker compose build`, so the image
  is always the one defined in `compose/*.yml`.
- `make test-<name>`, `make lint-<name>` and `make fmt-<name>` delegate to
  `services/<name>/Makefile` or `frontend/<name>/Makefile`, which must define
  the targets `test`, `lint` and `fmt`. Each component decides how to run its
  toolchain; the expectation is that tests and linters run inside a container
  (`docker build --target test`, `docker run` with the source mounted, or
  similar) so that no language toolchain has to be installed on the host.
- The aggregate targets `make test`, `make lint` and `make fmt` discover
  components by the presence of a `Makefile` in `services/*/` and `frontend/*/`.
- The service template (step P0.4) ships a component `Makefile` with these
  three targets, so every scaffolded component takes part automatically.
- `make lint` additionally lists remaining `TEMPORARY(P<step>)` markers
  (`CLAUDE.md`, section 8.7).

## Consequences

- The root `Makefile` stays language-agnostic and stable.
- A component without a `Makefile` is invisible to `make test`/`lint`/`fmt`;
  the documentation coverage check (step P0.9) and CI (step P0.6) must treat a
  missing component `Makefile` as an error.
- Three ways to run tests (root target, component target, raw docker command)
  must be kept consistent; the component `README.md` documents them.
