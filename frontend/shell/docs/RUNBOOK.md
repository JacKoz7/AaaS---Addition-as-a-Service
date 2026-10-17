# Runbook — `frontend-shell`

| Field | Value |
| --- | --- |
| Document | Operational Runbook |
| Component | `frontend-shell` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Quick Reference

| Item | Command |
| --- | --- |
| State | `make ps` |
| Logs | `make logs SVC=frontend-shell` (JSON access log) |
| Health | `docker compose exec frontend-shell wget -qO- http://127.0.0.1:8080/health` |
| Page | <http://127.0.0.1/> |
| Restart | `docker compose restart frontend-shell` |
| Rebuild | `make build-frontend-shell && make up` |

## 2. Alerts

Alerting is introduced in step P7.4; until then this section lists the
failure modes seen by the health check and by users.

### 2.1 Container unhealthy

- **Meaning**: `GET /health` (every 10 s, 2 s timeout) failed five times;
  nginx is not serving.
- **Diagnosis**: `make ps`; `make logs SVC=frontend-shell` for nginx errors
  (plain text on stderr), for example a broken `default.conf` after a change.
- **Remediation**: fix the configuration, `make build-frontend-shell && make up`.
- **Escalation**: CXT.

### 2.2 The page shows `Unavailable`

- **Meaning**: a key press got no 2xx answer after 3 attempts (gateway or
  `expression-assembler` down, or a `4xx`).
- **Diagnosis**: `make ps`; `make logs SVC=gateway`; `make logs SVC=expression-assembler`.
- **Remediation**: restore the service; press `C` and repeat the
  calculation.
- **Escalation**: CXT (expression-assembler), PEG (gateway).

### 2.3 The page shows `Error`

- **Meaning**: the task is `FAILED`, or it was still unknown 15 s after `=`.
- **Diagnosis**: an expression such as `2++3` is rejected by the parser
  (`make logs SVC=parser`, `expression rejected`); otherwise the ledger did
  not consume the task (`make logs SVC=ledger`).
- **Remediation**: none for a rejected expression; restore the ledger
  otherwise.
- **Escalation**: AEC (parser), TIO (ledger).

### 2.4 Progress does not move

- **Meaning**: the display shows `COUNTING n / b` without change.
- **Diagnosis and remediation**: ledger RUNBOOK §2.2 (successor down).

## 3. Data

The page stores nothing: no database, no cookies, no browser storage. A
reload starts a new session; a calculation in progress continues on the
server and its result stays in the ledger.
