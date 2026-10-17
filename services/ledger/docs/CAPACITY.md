# Capacity Plan — `ledger`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `ledger` |
| Owning Team | Transaction Integrity Office (TIO) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `ledger` | 64m | 0.5 | Compiled language: default limit for compiled services (CLAUDE.md 6.2); measured peak 3.7 MiB |
| `ledger-db` | 256m | 0.5 | Database: default limit (CLAUDE.md 6.2); measured peak 160 MiB |
| `ledger-db-init` | 32m | 0.25 | One-shot shell script with curl; exits within seconds of `ledger-db` being healthy |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up` on 2026-10-17
(Apple silicon host, Docker Desktop, linux/arm64 images), CLAUDE.md
section 8, rule 10.

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `ledger` | 2.7 MiB | 3.7 MiB | 2.3% | Three concurrent `15000 + 15000` additions | 2026-10-17 |
| `ledger-db` | 137.7 MiB | 159.5 MiB | 2.9% | Same; 15 entries and their checkpoints in the database | 2026-10-17 |

Timings through the gateway (`POST /api/v1/keys` … `=`, then polling
`GET /api/v1/tasks/{taskId}` every 0.5 s):

| Addition | Successor calls | Time to `RECORDED` |
| --- | --- | --- |
| `2 + 3`, `0 + 0`, `9 + 1` | 3, 0, 1 | 0.67–0.72 s |
| `1000 + 1000` | 1 000 | 2.29 s (2.3 ms per call) |
| `20000 + 20000`, ledger restarted at 5 549 calls | 20 000 | 56 s (about 4 s down) |
| Three `15000 + 15000` at once | 45 000 | 116 s for all three (2.6 ms per call in total) |

Without `TCP_NODELAY` on the client socket (`ledger/nodelay`, ADR-0017) a
successor call took 50 ms instead of 2 ms (measured: 49.9 ms average over 200
calls, 2.0 ms with the option). Graceful shutdown during an addition:
0.67 s (checkpoint written, Kafka closed).

The database volume held 1.3 MB after 15 entries (972 KB for the `ledger`
database, the rest immudb's system databases).

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). The waiting time of an addition grows linearly with the smaller
operand (CLAUDE.md section 1); capacity is planned for the largest addition,
99 999 + 99 999.

- **Memory** does not grow with the operands: a task holds a constant
  state (calls done, current value, one HTTP connection). It grows by a few
  kilobytes per concurrently counted task.
- **Time** is `b` successor calls: about 2.3 ms each with one task, so
  `99999 + 99999` needs about 4 minutes while the successor is computed
  natively (P2.13 adds the digit services to each call). Concurrent tasks
  share the successor and its CouchDB, the actual bottleneck (`cpus: 0.5`
  each).
- **Database** grows with every task and is never pruned (immudb is
  append-only, R-015): one row each in `processed_events` and `tasks`, one
  entry, one publication, and one version of the task row per checkpoint
  (every 1 000 calls, at most 100 per task).
