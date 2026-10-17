# Capacity Plan — `parser`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `parser` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `parser` | 64m | 0.5 | Compiled language (OCaml native code): default limit for compiled services (CLAUDE.md 6.2). The measured peak uses 12% of it. |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up`, idle and during an
addition (CLAUDE.md section 8, rule 10).

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `parser` | 7.1 MiB | 7.6 MiB | 3.4% of one core | 200 expressions with random operands through the gateway by 8 clients in 6.6 s (p50 13 ms, p95 79 ms per expression; RAM), then 300 in 20.2 s (CPU, `docker stats` sampled 25 times) | 2026-10-17, Apple silicon (arm64), Docker 27.5.1 |

The database is embedded, so there is no database container. The runtime
image is 38.7 MB.

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). The waiting time of an addition grows linearly with the smaller
operand (CLAUDE.md section 1); capacity is planned for the largest addition,
99 999 + 99 999.

The parser does constant work per expression whatever the operands: it
parses at most 64 characters once. Memory does not grow with the number of
expressions (each message is processed and released); only the SQLite file
grows, by roughly 1 KB per expression (`processed_events` with the output
event, plus one `ast_cache` row per distinct expression text), without a
retention job (R-012).
