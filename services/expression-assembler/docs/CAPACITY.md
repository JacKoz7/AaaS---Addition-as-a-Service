# Capacity Plan — `expression-assembler`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `expression-assembler` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `expression-assembler` | 128m | 0.5 | Deviation from the 64 MB default for compiled languages (`CLAUDE.md` 6.2): .NET runs IL on a JIT runtime with a garbage collector, plus the native librdkafka client, which is closer to an interpreted runtime; the 128 MB default of interpreted languages applies. The GC heap is capped at 70% of the limit. |
| `expression-assembler-db` | 256m | 0.5 | Database default (`CLAUDE.md` 6.2). SurrealKV defaults (256 MiB memtable, 3 GiB block cache) are reduced to 16 MiB each in Compose so that the store fits. |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up` (`CLAUDE.md`
section 8, rule 10), Docker Desktop on arm64, 2026-10-17.

| Container | Idle RAM | Peak RAM | Scenario |
| --- | --- | --- | --- |
| `expression-assembler` | 52.8 MiB | 54.5 MiB | 20 sessions × (10 parallel key presses + `=`), 220 requests in 2 s |
| `expression-assembler-db` | 92–126 MiB | 146 MiB | Same scenario; the idle figure varies with SurrealDB background work |

Latency through the gateway, warm, single client: 11 ms per key press,
19 ms for `=` (first request after start: 46 ms). Disk: about 1 MB for
roughly 250 presses and 25 tasks (about 4 KB per press, write-ahead log
included).

Before token authentication was introduced (ADR-0014), each query verified
the password hash and the same scenario took 52 s with key presses averaging
1.6 s; the measurement is kept here as the reason for the design.

## 3. Scaling Notes

An addition costs this service one request per key (at most 12 for
`99999+99999=`), independent of the size of the operands: the waiting time
of AaaS grows behind it, in the successor loop. Storage grows by about 4 KB
per press with no retention job yet (R-012). One replica runs on a single
host; the service holds no state in memory except the SurrealDB token.
