# ADR-0004: Service scaffolding with explicit TODO(scaffold) markers

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-16 |
| Deciders | Platform Enablement Guild (PEG) |
| Step | P0.4 |

## Context

`CLAUDE.md` asks for a service template and a one-command generator. The 35
services use 28 languages and 13 database products, so a single template
cannot contain a working build for every one of them. Two options were
considered: per-language templates (28 Dockerfiles to maintain before any
service exists) or a language-agnostic skeleton whose language-specific parts
are filled in by the step that implements the service.

A skeleton creates a risk: an unfinished scaffold could be committed and
break `make up`, because Compose would try to build it.

## Decision

- `templates/service/` holds **one language-agnostic template**: `Dockerfile`
  with a fixed stage contract (`toolchain`, `lint`, `test`, `build`,
  `runtime`), a component `Makefile` (ADR-0002) that runs every target through
  those stages, `README.md`, `.dockerignore` and Compose block fragments.
- `scripts/new-service.sh <name> <language>` renders the template with
  `__PLACEHOLDER__` substitution. It carries the **service catalog** from
  `CLAUDE.md` section 2 (team, database, purpose), so a catalog service needs
  no extra arguments; the language argument is cross-checked against the
  catalog and a mismatch is a warning, not an error, because deviations are
  allowed with an ADR.
- Everything the template cannot know is marked **`TODO(scaffold)`**: base
  images, lint/test/build commands, database image, data path and readiness
  check, entrypoint, formatter. The `lint`, `test` and `build` stages
  deliberately `exit 1` until replaced.
- `make lint` runs `lint-scaffold`, which **fails while any `TODO(scaffold)`
  marker exists** outside `templates/` and `docs/`. Since `make lint` is in the
  Definition of Done, an unfinished scaffold cannot close a step.
- Databases are either **containers** (`<name>-db` in Compose, on the `data`
  network, `depends_on: service_healthy`) or **embedded** (SQLite, Mnesia,
  BoltDB, LMDB, Raft stores): the service mounts the `<name>-data` volume
  itself and no database container is generated.
- `compose/services.yml` keeps a `# AAAS:VOLUMES` marker; service blocks are
  inserted above it and volume entries appended after it. A service is
  inserted at most once; the script refuses an existing directory or block.
- Memory limits follow `CLAUDE.md` 6.2 by language class (compiled 64 MB,
  interpreted 128 MB, JVM 512 MB, databases 256 MB) and the generated block
  carries the justification comment.
- Corporate documents are copied from `templates/docs/` when that directory
  exists (step P0.7); until then `docs/` is created empty.

## Consequences

- A scaffold is a starting point, never a runnable service; the step that
  creates a service must replace every marker before closing.
- The stage contract lets the root `Makefile`, CI (P0.6) and the documentation
  coverage check (P0.9) treat every service identically.
- Off-the-shelf components (Traefik, Keycloak, Consul, OpenBao, Apicurio,
  Debezium, Unleash, etcd) are scaffolded the same way; their "language" is the
  product name and their Dockerfile wraps the vendor image.
- Microfrontends are not covered; Phase 8 decides whether they get a generator.
