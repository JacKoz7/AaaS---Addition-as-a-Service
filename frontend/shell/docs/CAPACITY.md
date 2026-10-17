# Capacity Plan — `frontend-shell`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `frontend-shell` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `frontend-shell` | 64m | 0.25 | Static files from nginx: the default of a compiled service (CLAUDE.md 6.2) is ample; measured peak 7.4 MiB |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up` on 2026-10-17
(Apple silicon host, linux/arm64 image), CLAUDE.md section 8, rule 10.

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `frontend-shell` | 7.3 MiB | 7.4 MiB | 0.5% | Headless Chromium: `2+3=`, `C`, `12+30=`, `7+0=`, `2++3=` | 2026-10-17 |

The runtime image is 90 MB; the page is 8 files of 35 KB in total (most of it documentation comments).
In the browser, `2 + 3` shows `5` 1.2 s after `=` (one poll of up to
1 s after the ledger records the result).

## 3. Scaling Notes

nginx serves static files; its usage does not depend on the operands. The
browser sends one request per key press and one status request per second
while a task runs, so a 30-minute addition costs about 1 800 status
requests.
