# ADR-0003: Compose network topology and include layout

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-16 |
| Deciders | Platform Enablement Guild (PEG) |
| Step | P0.3 |

## Context

`CLAUDE.md` 6.2 prescribes three networks (`public`, `services`, `data`), a root
`docker-compose.yml` that only includes files from `compose/`, and one Compose
profile per file. It leaves open where the networks are declared, how they are
named in Docker, and whether the `data` network may reach the outside world.
Compose `include` loads each file as an independent model and merges them, so
duplicate declarations with differing attributes are rejected.

## Decision

- Networks are declared **once, in the root `docker-compose.yml`**. Included
  files only reference them by their Compose name (`public`, `services`,
  `data`). Verified with Compose v2.32: a service in an included file may
  reference a network declared in the root file.
- Docker-level names are prefixed with the project name: `aaas-public`,
  `aaas-services`, `aaas-data`, so they are recognizable in `docker network ls`
  next to other projects on the same host.
- `data` is declared `internal: true`. Containers attached only to `data`
  (every database) have no route to the host network or the internet, which
  makes rule 4 of `CLAUDE.md` ("a service never reaches another service's
  database") enforceable at the network level: a database is reachable only by
  containers that are explicitly attached to `data`, and the P0.4 template
  attaches a service to `data` solely for its own database.
- `public` is the only network whose members publish ports on the host.
- `make up` on a model that defines no services for the selected profiles
  prints a notice and exits 0 instead of propagating Compose's
  "no service selected" error, so the skeleton can be exercised before the
  first service exists.

## Consequences

- Databases cannot download anything at runtime (no egress). Images must
  contain everything they need; extensions are baked into the image.
- A service that needs both its database and other services joins both
  `services` and `data`; this is the default in the P0.4 template.
- Adding a fourth network requires editing only the root file.
- Compose prunes unreferenced networks from `docker compose config` output;
  the networks appear once a service references them.
