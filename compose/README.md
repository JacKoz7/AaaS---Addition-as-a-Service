# Compose files

`docker-compose.yml` at the repository root declares the project name `aaas`,
the three networks and includes one file per Compose profile from this
directory. No service is defined in the root file.

| File | Profile | Owning team | Content |
| --- | --- | --- | --- |
| `core.yml` | `core` | PEG | Redpanda, topic job and Console (P1.1, [ADR-0011](../docs/adr/0011-event-bus-redpanda.md), [`infra/redpanda/`](../infra/redpanda/README.md)), Temporal + UI + PostgreSQL (P3.2) |
| `services.yml` | `services` | PEG | The 35 microservices and their databases |
| `frontend.yml` | `frontend` | CXT | single-spa shell and microfrontends (nginx) |
| `observability.yml` | `observability` | OSG | OTel Collector, Prometheus, Loki, Jaeger, Grafana, Alertmanager |
| `aws-local.yml` | `aws-local` | CGC | Floci AWS emulator; excluded from `make up` |

## Networks

| Network | Docker name | Members | Published ports |
| --- | --- | --- | --- |
| `public` | `aaas-public` | gateway, microfrontends, operator UIs that publish a port (Redpanda Console) | yes (only the gateway publishes `80`; UIs listed in `CLAUDE.md` 6.2 publish their own) |
| `services` | `aaas-services` | every service, Redpanda, Temporal, observability | no |
| `data` | `aaas-data` | databases and the single service that owns each one | no (`internal: true`, no egress) |

A service joins `data` only to reach its own database (`CLAUDE.md` rule 4).
Databases never join `services`.

## Rules for every service block

Taken from `CLAUDE.md` 6.2 and enforced by the P0.4 template:

- `profiles:` set to the file's profile.
- `mem_limit` and `cpus` always present; defaults 64 MB (compiled languages),
  128 MB (interpreted), 512 MB (JVM), 256 MB (databases). Deviations carry a
  comment.
- `healthcheck` in Compose, not in the Dockerfile.
- `depends_on` with `condition: service_healthy`.
- Volumes named `<service>-data`.
- Base images pinned to a version, multi-arch (`linux/arm64` and `linux/amd64`).

## Running

```sh
make up                      # core,services,frontend,observability
make up PROFILES=core        # one profile (Redpanda, topics, Console)
make topics-check            # topics match contracts/events/topics.psv
make up PROFILES=aws-local   # Floci only
docker compose config        # render the merged model
```

Environment variables come from `.env` (copy `.env.example`); the root file
sets `name: aaas`, so the project name does not depend on `.env`.
