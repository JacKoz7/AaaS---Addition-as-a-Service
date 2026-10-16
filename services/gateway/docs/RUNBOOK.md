# Runbook — `gateway`

| Field | Value |
| --- | --- |
| Document | Operational Runbook |
| Component | `gateway` |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-16 |

## 1. Quick Reference

| Item | Command |
| --- | --- |
| State | `make ps` |
| Logs | `make logs SVC=gateway` (Traefik log and access log, JSON) |
| Health | `docker compose exec gateway wget -qO- http://127.0.0.1:8080/health` |
| Metrics | `docker compose exec gateway wget -qO- http://127.0.0.1:8080/metrics` |
| Public entry | `curl -i http://127.0.0.1/api/v1/tasks/<taskId>` |
| Restart | `docker compose restart gateway` |
| Rebuild | `make build-gateway && make up` |
| Configuration | `services/gateway/config/` (baked into the image; rebuild after a change) |

## 2. Alerts

Every alert defined for this service has one section below: meaning,
diagnosis step by step, remediation, escalation. Alerting is introduced in
step P7.4; until then this section lists the failure modes detected by the
Compose health check and by callers.

### 2.1 Container unhealthy

- **Meaning**: the Compose health check (`GET /health` on port 8080, every
  10 s, 2 s timeout) failed five times in a row after the 10 s start period.
  The health endpoint answers as soon as Traefik serves requests with its
  dynamic configuration loaded and the `edge` plugin running; it does not
  depend on any upstream.
- **Diagnosis**:
  1. `make ps` — confirm the state of `gateway` and its restart count.
  2. `make logs SVC=gateway` — look for `"level":"error"` entries; typical
     causes are a YAML or template error in `config/dynamic/routes.yml`
     (the `health` router is then missing, so `/health` answers 404) or a
     plugin that fails to load (the startup log lacks "Plugins loaded.").
  3. `docker inspect aaas-gateway-1 --format '{{.State.OOMKilled}}'` —
     memory exhaustion (limit 64 MB, see CAPACITY.md).
- **Remediation**: fix the configuration or plugin, `make build-gateway`,
  `make test-gateway` (the integration test starts Traefik with the same
  files), then `make up`.
- **Escalation**: Platform Enablement Guild (PEG), then the repository owner
  (RACI.md).

### 2.2 API returns 502 Bad Gateway problems

- **Meaning**: the upstream of the route could not be reached after three
  attempts (connection refused, unknown host). Until the service of a route
  is delivered (expression-assembler P1.4, ledger P1.7, frontend-shell P1.8)
  this is the expected answer of that route.
- **Diagnosis**:
  1. The `instance` member of the problem names the path; the access log
     entry with that `RequestPath` names `ServiceName` and `ServiceURL`.
  2. `make ps` — is the upstream container running and healthy?
  3. `docker compose exec gateway wget -qO- <ServiceURL>/health` — reach the
     upstream from the gateway's network.
- **Remediation**: restore the upstream service (its own RUNBOOK.md).
- **Escalation**: the team owning the upstream (CXT for expression-assembler
  and frontend, TIO for ledger and saga-orchestrator).

### 2.3 API returns 504 Gateway Timeout problems

- **Meaning**: the upstream accepted the connection but sent no response
  headers within 2 s (`responseHeaderTimeout`, CLAUDE.md 6.1).
- **Diagnosis**: access log `Duration` ≈ 2 s for the route; check the
  upstream's logs and CPU (`docker stats`).
- **Remediation**: fix the slow upstream; the timeout is a contract and is
  not raised to hide a slow service.
- **Escalation**: the team owning the upstream.

### 2.4 Port 80 already in use

- **Meaning**: `make up` fails with "address already in use" for
  `127.0.0.1:80`.
- **Diagnosis**: `lsof -nP -iTCP:80 -sTCP:LISTEN` on the host.
- **Remediation**: stop the other process; the published port is fixed by
  `CLAUDE.md` 6.2.
- **Escalation**: none (host configuration).

## 3. Database

None until P5.4, when the Redis route table is introduced; the gateway
keeps no state, so a restart loses nothing but requests in flight, which
are given 8 s to finish (`graceTimeOut`).
