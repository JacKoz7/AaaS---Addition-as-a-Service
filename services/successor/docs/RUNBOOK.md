# Runbook — `successor`

| Field | Value |
| --- | --- |
| Document | Operational Runbook |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Quick Reference

| Item | Command |
| --- | --- |
| State | `make ps` |
| Logs | `make logs SVC=successor` |
| Health | `docker compose exec successor wget -qO- http://127.0.0.1:8080/health` |
| Metrics | `GET /metrics` on port 8080 |
| Restart | `docker compose restart successor` |
| Rebuild | `make build-successor && make up` |

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
  1. `make ps` — confirm the state of `successor`.
  2. `make logs SVC=successor` — look for `level":"error"` entries.
  3. Check the `checks` object of the last `/health` response for the failing
     dependency.
- **Remediation**: fix the failing dependency, then
  `docker compose restart successor`.
- **Escalation**: Arithmetic Excellence Center (AEC), then PEG (RACI.md).

The checks of `/health`: `database` (`GET /successor_calls` answers 200)
and `broker` (a metadata request for `aaas.successor.called.v1` answers
within 1 s).

### 2.2 Calls failing with 503

- **Meaning**: `successor_calls_total{outcome="failed"}` and
  `successor_dependency_failures_total{dependency}` grow; the log has
  `"msg":"successor call failed"` with `dependency` (`couchdb` or `kafka`)
  and `error`. The caller receives a 503 problem and retries; additions
  slow down but stay correct.
- **Diagnosis**:
  1. `dependency` of the log line.
  2. CouchDB: `make ps`, `docker compose logs successor-db`, free space of
     the `successor-data` volume (`docker system df -v`).
  3. Kafka: `docker compose exec redpanda rpk cluster health`; librdkafka
     lines in the log (`"msg":"librdkafka"`).
- **Remediation**: restore the dependency; nothing else is needed, retried
  calls are answered from the call log.
- **Escalation**: PEG for Redpanda, AEC otherwise.

### 2.3 Many replayed calls

- **Meaning**: `successor_calls_total{outcome="replayed"}` grows fast: the
  caller retries calls that had succeeded, usually because its timeout is
  shorter than the call latency.
- **Diagnosis**: compare `successor_call_duration_seconds` with the
  caller's timeout; check CouchDB latency.
- **Remediation**: fix the slow dependency or the caller's timeout.
- **Escalation**: TIO (owner of the caller).

### 2.4 Arguments rejected

- **Meaning**: `successor_calls_total{outcome="rejected"}` grows; the log
  has `"argument outside the domain"`. A caller asked for the successor of
  a number outside `0..199997`, or sent a malformed body: a defect of the
  caller.
- **Escalation**: TIO.

## 3. Database (CouchDB, container)

CouchDB is reachable only on the `data` network; use `curl` inside its
container:

```sh
docker compose exec successor-db curl -s -u successor:"$SUCCESSOR_DB_PASSWORD" \
  http://127.0.0.1:5984/successor_calls
docker compose exec successor-db curl -s -u successor:"$SUCCESSOR_DB_PASSWORD" \
  "http://127.0.0.1:5984/successor_calls/_design/call_log/_view/by_task?startkey=%5B%22<taskId>%22%5D&endkey=%5B%22<taskId>%22,%7B%7D%5D"
```

- **Backup**: stop `successor` and copy the volume `aaas_successor-data`
  (`/opt/couchdb/data`); restore by copying it back.
- **Loss of the database**: the call log of past additions is gone; the
  migrations recreate the databases at the next start. A call of an
  addition in progress is then logged again and its event published with a
  new `eventId` (consumers deduplicate by `eventId`; the audit topic has
  no consumer yet).
- **In-flight additions**: a call is answered only after it is logged and
  published, so stopping the service at any moment leaves the caller to
  retry the same call, which is safe.
