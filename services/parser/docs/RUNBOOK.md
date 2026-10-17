# Runbook — `parser`

| Field | Value |
| --- | --- |
| Document | Operational Runbook |
| Component | `parser` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Quick Reference

| Item | Command |
| --- | --- |
| State | `make ps` |
| Logs | `make logs SVC=parser` |
| Health | `docker compose exec parser wget -qO- http://127.0.0.1:8080/health` |
| Metrics | `GET /metrics` on port 8080 |
| Restart | `docker compose restart parser` |
| Rebuild | `make build-parser && make up` |

## 2. Alerts

Every alert defined for this service has one section below: meaning,
diagnosis step by step, remediation, escalation. Alerting is introduced in
step P7.4; until then this section lists the failure modes detected by the
Compose healthcheck.

### 2.1 Container unhealthy

- **Meaning**: the Compose healthcheck (`GET /health`, every 10 s, 3 s
  timeout) failed five times in a row after the 20 s start period;
  dependants that wait with `condition: service_healthy` do not start.
- **Diagnosis**:
  1. `make ps` — confirm the state of `parser`.
  2. `make logs SVC=parser` — look for `level":"error"` entries.
  3. Check the `checks` object of the last `/health` response for the failing
     dependency.
- **Remediation**: fix the failing dependency, then
  `docker compose restart parser`.
- **Escalation**: Arithmetic Excellence Center (AEC), then PEG (RACI.md).

The three checks of `/health` mean:

| Check | Fails when | Usual cause |
| --- | --- | --- |
| `database` | `SELECT 1` on the SQLite file fails | Volume missing or full, file permissions |
| `broker` | No TCP connection to the first broker within 1 s | Redpanda stopped or restarting |
| `consumer` | The last poll ended more than 15 s ago | A message is being retried (see 2.3), or Kafka is unreachable |

### 2.2 Expressions rejected

- **Meaning**: `parser_expressions_rejected_total{reason}` grows; the log has
  `"msg":"expression rejected"` with `reason` and `detail`. The user typed
  something that is not `number + number` (for example `2++3`), or, until
  P2.17, an operand above 99 999.
- **Diagnosis**: `make logs SVC=parser | grep 'expression rejected'` and
  search for the `taskId`; the stored reason is in
  `processed_events.reason` (see section 3 for reading the database).
- **Remediation**: none; this is the intended behaviour. Until P3.6 the
  task stays without a result (`TEMPORARY(P3.6)`).
- **Escalation**: only if valid additions are rejected: AEC.

### 2.3 Processing failing and retried

- **Meaning**: `parser_processing_failures_total` grows; the log has
  `"processing failed; retrying"` (`warn`, first three attempts) or
  `"processing failed, local retries exhausted; retrying in place"`
  (`error`, every 5 s). The message is neither lost nor skipped: its offset
  is not stored until it succeeds. Typical errors: `Kafka.Error` or
  `Lwt_unix.Timeout` (broker), `Store.Error` (database).
- **Diagnosis**:
  1. `error` field of the log line.
  2. Broker: `make ps`, `docker compose exec redpanda rpk cluster health`.
  3. Database: free space of the `parser-data` volume
     (`docker system df -v`).
- **Remediation**: restore the dependency; processing resumes by itself
  and publishes the stored event (outcome `republished`).
- **Escalation**: PEG for Redpanda, AEC otherwise.

### 2.4 Messages discarded

- **Meaning**: `parser_events_consumed_total{outcome="discarded"}` grows; the
  log has `"message discarded"` with the reason. A message on
  `aaas.expression.submitted.v1` is not such an event (not JSON, wrong
  `type` or `version`, missing identifiers). Only the expression-assembler
  may produce on that topic.
- **Diagnosis**: find the producer of the message (Redpanda Console,
  port 8082).
- **Remediation**: stop the foreign producer. Until P3.6 the message is
  only logged (`TEMPORARY(P3.6)`), afterwards it goes to `aaas.dlq.v1`.
- **Escalation**: PEG (topic ownership), TIB if the producer is unknown.

### 2.5 librdkafka diagnostics

librdkafka's own log lines are plain text, so they are disabled by default
(`AAAS_KAFKA_LOG_LEVEL=0`). For a broker connection problem, set
`AAAS_KAFKA_LOG_LEVEL=6` in `compose/services.yml` temporarily and restart
the service; the lines appear on stderr.

### 2.6 Second instance started

The parser consumes all partitions itself (ADR-0015); a second instance
would process every event twice in two databases and publish two different
`eventId`s per task. Never scale the service beyond one replica (R-013).

## 3. Database (SQLite, embedded)

The file is `/data/parser.db` (WAL mode, plus `-wal` and `-shm` files) in
the volume `parser-data`. The runtime image has no SQLite shell; inspect a
copy instead:

```sh
docker compose stop parser
docker run --rm -v aaas_parser-data:/data -v "$PWD":/out alpine:3.22.2 \
  sh -c 'apk add -q sqlite && sqlite3 /data/parser.db ".backup /out/parser.db"'
docker compose start parser
sqlite3 parser.db "SELECT status, count(*) FROM processed_events GROUP BY status"
```

- **Backup and restore**: copy the file with `.backup` as above while the
  service is stopped; restore by copying it back into the volume.
- **Loss of the database**: the AST cache is rebuilt by itself. The
  idempotency record is lost: events whose offsets are not yet committed
  (at most the last second) would be processed again and published with a
  new `eventId`. The consumers deduplicate by `taskId` (the saga's workflow
  ID from P3.3).
- **In-flight additions**: a row in status `pending` is republished on the
  next delivery of its event, so stopping the service at any moment loses
  nothing.
- **Migrations** run at startup; `migrationsApplied` in the
  `database ready` log line tells how many were new.
