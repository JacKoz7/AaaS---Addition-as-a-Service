# Runbook — `expression-assembler`

| Field | Value |
| --- | --- |
| Document | Operational Runbook |
| Component | `expression-assembler` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Quick Reference

| Item | Command |
| --- | --- |
| State | `make ps` |
| Logs | `make logs SVC=expression-assembler` (JSON: `ts`, `level`, `service`, `msg`, `taskId`, `traceId`, `spanId`) |
| Health | `docker compose exec expression-assembler wget -qO- http://127.0.0.1:8080/health` |
| Metrics | `docker compose exec expression-assembler wget -qO- http://127.0.0.1:8080/metrics` |
| Events | `docker compose exec redpanda rpk topic consume aaas.expression.submitted.v1 --offset start --num 1` |
| Database shell | `docker compose exec expression-assembler-db /surreal sql --endpoint http://127.0.0.1:8000 --user expression_assembler --pass "$EXPRESSION_ASSEMBLER_DB_PASSWORD" --ns aaas --db expression_assembler` |
| Restart | `docker compose restart expression-assembler` |
| Rebuild | `make build-expression-assembler && make up` |

## 2. Alerts

Alerting is introduced in step P7.4; until then this section lists the
failure modes detected by the Compose health check and by callers.

### 2.1 Container unhealthy

- **Meaning**: `GET /health` failed five times in a row after the 30 s start
  period. It answers 503 when SurrealDB does not answer `RETURN 1` or
  Redpanda does not answer a metadata request within one second; the body
  names the failing check.
- **Diagnosis**:
  1. `docker compose exec expression-assembler wget -qO- http://127.0.0.1:8080/health`
     — read `checks.database` and `checks.broker` (wget prints nothing on
     503; use `-S` to see the status, or the logs).
  2. `make ps` — are `expression-assembler-db` and `redpanda` healthy?
  3. `make logs SVC=expression-assembler` — `"level":"warn"` lines
     `key press answered 503 (database|broker|deadline): …` carry the cause.
  4. `docker inspect aaas-expression-assembler-1 --format '{{.State.OOMKilled}}'`
     — memory exhaustion (limit 128 MB, CAPACITY.md).
- **Remediation**: restore the failing dependency (its runbook, or
  `docker compose restart expression-assembler-db`); the service recovers by
  itself: the SurrealDB token is renewed and the Kafka producer reconnects.
- **Escalation**: CXT, then PEG for Redpanda, then the repository owner.

### 2.2 Container exits at startup

- **Meaning**: the process ended with exit code 1 before serving.
- **Diagnosis**: `docker compose logs expression-assembler`:
  - `invalid configuration: …` — a required variable is missing
    (`AAAS_KAFKA_BROKERS`, `AAAS_DB_URL`, `EXPRESSION_ASSEMBLER_DB_PASSWORD`)
    or `AAAS_BOOTSTRAP` is not `env`;
  - `database not ready (attempt N)` repeated 15 times, then
    `database migration failed` — SurrealDB unreachable for 30 s or the
    password differs from the one the database volume was created with;
  - `Failed to load the librdkafka native library` — the runtime image lacks
    `cyrus-sasl` (Dockerfile).
- **Remediation**: fix the configuration or the image; a password mismatch
  requires the original password or a new volume (`make clean` deletes all
  stored presses and tasks).
- **Escalation**: CXT.

### 2.3 Key presses answered 503

- **Meaning**: `expression_assembler_rejected_total{reason}` grows with
  reason `database`, `broker` or `deadline`. The client sees an RFC 9457
  problem and may retry; retries are safe.
- **Diagnosis**: the warning log line names the dependency and the error;
  `deadline` means the 1.8 s request budget expired (a slow dependency).
- **Remediation**: restore the dependency. Events stored but not yet
  published are published when the client retries the same request; there
  is no background republisher in 0.1.0 (see THREAT_MODEL.md, residual risk).
- **Escalation**: CXT, then PEG (Redpanda).

### 2.4 Conflicts (409) reported by users

- **Meaning**: the frontend reused a `seq` with another key or an
  `Idempotency-Key` for another `=` press.
- **Diagnosis**: the problem `detail` names the case; check the frontend's
  sequence numbering.
- **Remediation**: fix the client; the service is behaving as specified.
- **Escalation**: CXT (frontend).

## 3. Database

SurrealDB 3.3 in `expression-assembler-db`, data in the volume
`expression-assembler-data` (mounted on `/home/nonroot`). The schema is
created by the migrations at service startup. A restart of either container
loses nothing; `make clean` deletes the volume and every stored press and
task. Backups are not taken in Phase 1: the data has no value after the
task has been submitted (DATA_CLASSIFICATION.md).
