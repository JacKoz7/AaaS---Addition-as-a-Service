# Runbook — `ledger`

| Field | Value |
| --- | --- |
| Document | Operational Runbook |
| Component | `ledger` |
| Owning Team | Transaction Integrity Office (TIO) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Quick Reference

| Item | Command |
| --- | --- |
| State | `make ps` |
| Logs | `make logs SVC=ledger` (database: `SVC=ledger-db`, provisioning: `SVC=ledger-db-init`) |
| Health | `docker compose exec ledger wget -qO- http://127.0.0.1:8080/health` |
| Metrics | `docker compose exec ledger wget -qO- http://127.0.0.1:8080/metrics` |
| Task status | `curl -s http://127.0.0.1/api/v1/tasks/<taskId>` |
| Restart | `docker compose restart ledger` (counting tasks checkpoint and resume) |
| Rebuild | `make build-ledger && make up` |

## 2. Alerts

Alerting is introduced in step P7.4; until then this section lists the
failure modes detected by the Compose health check and the logs.

### 2.1 Container unhealthy

- **Meaning**: `GET /health` (every 10 s, 3 s timeout) failed five times in
  a row after the 30 s start period. `/health` answers from the last
  checks: `database` (a query every 5 s) and `broker` (librdkafka
  statistics every 5 s, both the consumer and the producer must see a
  broker `UP`).
- **Diagnosis**:
  1. `make ps` — state of `ledger`, `ledger-db`, `redpanda`.
  2. The `checks` object of `/health` names the failing dependency.
  3. `make logs SVC=ledger` — `database not ready, retrying`,
     `storing the event failed`, `append failed`, `kafka error`.
- **Remediation**: restore the dependency (§3, `make up` for Redpanda); the
  ledger reconnects by itself (new immudb session on the next request,
  librdkafka reconnects). No restart is needed.
- **Escalation**: TIO, then PEG for Redpanda (RACI.md).

### 2.2 Additions do not progress

- **Meaning**: a task stays `COUNTING` with the same `progress.done`.
- **Diagnosis**:
  1. `curl -s http://127.0.0.1/api/v1/tasks/<taskId>` twice, 5 s apart.
  2. `ledger_successor_calls_total` by `outcome`: `unavailable`, `timeout`
     or `error` growing means the successor (or its CouchDB) is down.
  3. `make logs SVC=successor`.
- **Remediation**: restore the successor; the ledger retries the same call
  (backoff up to 5 s, `TEMPORARY(P3.6)`: without limit) and continues. A
  repeated call is safe: the successor answers it from its call log.
- **Escalation**: AEC (owner of `successor`).

### 2.3 Task `FAILED`

- **Meaning**: the successor refused a call with a 4xx (for example an
  argument outside 0..199 997); the task can never be recorded.
- **Diagnosis**: log line `successor refused a call; task failed`; the
  column `tasks.failure` holds the answer.
- **Remediation**: none for the task (a new `=` creates a new task). Report
  the defect to AEC: with operands checked by the parser this cannot
  happen.
- **Escalation**: AEC.

### 2.4 Event rejected

- **Meaning**: log line `event rejected`; a consumed message is not a valid
  `aaas.addition.requested.v1` (`ledger_events_consumed_total{outcome="rejected"}`).
  `TEMPORARY(P3.6)`: it is skipped; from P3.6 it goes to `aaas.dlq.v1`.
- **Diagnosis**: the `error` field names the field; the offset and
  partition are in the line.
- **Escalation**: AEC (owner of the producer, `parser`).

## 3. Database (immudb, container `ledger-db`)

The ledger user and its database are created by the one-shot container
`ledger-db-init` ([`immudb/provision.sh`](../immudb/provision.sh)), which
must exit 0 before the ledger starts. A query as the ledger user:

```sh
N=aaas-data; c() { docker run --rm --network $N curlimages/curl:8.17.0 -s "$@"; }
B=http://ledger-db:8080/api
T=$(c -X POST $B/login -d "{\"user\":\"$(printf ledger | base64)\",\"password\":\"$(printf "$LEDGER_DB_PASSWORD" | base64)\"}" | sed 's/.*"token":"\([^"]*\)".*/\1/')
T=$(c -H "Authorization: Bearer $T" $B/db/use/ledger | sed 's/.*"token":"\([^"]*\)".*/\1/')
c -X POST $B/db/sqlquery -H "Authorization: Bearer $T" -d '{"sql":"SELECT task_id, status, done, b FROM tasks"}'
```

(`LEDGER_DB_PASSWORD` defaults to `change-me`, `.env.example`.)

### 3.1 Unpublished entries

`SELECT entry_seq FROM ledger_entries` against
`SELECT entry_seq FROM publications`: entries after the highest published one
are published again at the next start (`recovery done`, field
`republished`). Consumers deduplicate by `eventId`.

### 3.2 Chain check

Until `GET /api/v1/ledger/verify` (P3.7), pipe the answer of
`SELECT entry_seq, task_id, a, b, result, recorded_at, prev_hash, hash FROM ledger_entries ORDER BY entry_seq`
into:

```sh
python3 -c '
import sys, json, hashlib
prev = "0" * 64
for r in json.load(sys.stdin)["rows"]:
    s, t, a, b, res, at, ph, h = [x.get("s", x.get("n")) for x in r["values"]]
    assert ph == prev, ("broken link at", s)
    assert hashlib.sha256("|".join([ph, t, a, b, res, at]).encode()).hexdigest() == h, ("bad hash at", s)
    prev = h
print("chain OK")'
```

### 3.3 Restart, loss and passwords

- **Restart of `ledger-db`**: the ledger reports `database: failing`,
  retries every write (checkpoint failures are logged and skipped) and
  continues when immudb is back.
- **Loss of the volume `ledger-data`** (`make clean`): the chain restarts at
  entry 1 and every task is forgotten; events already committed are not
  consumed again. Do not delete the volume outside development.
- **Passwords**: `LEDGER_DB_ADMIN_PASSWORD` and `LEDGER_DB_PASSWORD` are
  applied when the volume and the user are created. Changing them later in
  `.env` does not change the stored passwords: change them in immudb
  (`immuadmin` in the `ledger-db` container) or recreate the volume.
