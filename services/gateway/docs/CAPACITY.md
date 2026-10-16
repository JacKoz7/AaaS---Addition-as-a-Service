# Capacity Plan — `gateway`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `gateway` |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-16 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `gateway` | 64m | 0.5 | Traefik is a compiled Go binary: default limit for compiled services (`CLAUDE.md` 6.2). The measurement below leaves more than half of the limit free. |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up` (CLAUDE.md
section 8, rule 10). No addition can run yet in Phase 1 before P1.7, so the
load scenario is synthetic.

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `gateway` | — | 27.4 MiB | < 1% after the burst | 2 000 requests to unknown `/api` paths (404 problems) and 40 requests to an absent upstream (502 problems after retries), 20 in parallel | 2026-10-16, Docker Desktop (arm64) |

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). The waiting time of an addition grows linearly with the smaller
operand (CLAUDE.md section 1), but the gateway does not: an addition costs
the gateway one `POST /api/v1/keys` per key press and one
`GET /api/v1/tasks/{taskId}` per second of waiting (display polling) plus,
from P8.17, one long-lived SSE connection. For 99 999 + 99 999 (up to
35 minutes) that is about 2 100 status requests, a negligible load.
