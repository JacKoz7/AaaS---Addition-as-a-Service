# Capacity Plan — `successor`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `successor` | 64m | 0.5 | Compiled language (GHC native code): default limit for compiled services (CLAUDE.md 6.2); the GHC heap is capped at 40 MB (`-M40m`), leaving room for librdkafka and the RTS. |
| `successor-db` | 256m | 0.5 | Database default (CLAUDE.md 6.2). |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up`, idle and during an
addition (CLAUDE.md section 8, rule 10).

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `successor` | 16.3 MiB | 43.1 MiB | 12.8% of one core | 2000 sequential calls of one task (`n` = 1000 … 2999, the steps of 1000 + 2000) over one keep-alive connection in 4.7 s: p50 2.0 ms, p95 3.6 ms, p99 5.7 ms, max 42.3 ms | 2026-10-17, Apple silicon (arm64), Docker 27.5.1 |
| `successor-db` | 95.9 MiB | 139.9 MiB | 15.9% of one core | same scenario | 2026-10-17, Apple silicon (arm64), Docker 27.5.1 |

Idle values are from a fresh `make clean && make up`. Under load the
GHC runtime grows its allocation areas and librdkafka its buffers to about
43 MiB, which stays flat however many calls follow.

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). The waiting time of an addition grows linearly with the smaller
operand (CLAUDE.md section 1); capacity is planned for the largest addition,
99 999 + 99 999.

Memory of the service is constant per call. Time grows linearly with the
smaller operand: at the measured 2.35 ms per call (including the caller's
round trip), 99 999 calls take about 4 minutes in the successor alone,
before the digit services join in P2.13. The call log grows by one
document per call: 2000 calls took 6.4 MB on disk before compaction (about
3.2 KB per call; 0.5 KB of JSON each), so 99 999 + 99 999 adds about
320 MB until CouchDB compacts the database (R-014).
