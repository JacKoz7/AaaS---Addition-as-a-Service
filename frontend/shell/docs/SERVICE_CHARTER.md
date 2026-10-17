# Service Charter — `frontend-shell`

| Field | Value |
| --- | --- |
| Document | Service Charter |
| Component | `frontend-shell` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Service Version | 0.1.0 |
| Last Reviewed | 2026-10-17 |
| Review Cadence | On every minor version, and at least once per phase |

## 1. Mission

The calculator of AaaS: a keypad and a display (`CLAUDE.md` 1), served as
one plain-JavaScript page behind the gateway. `TEMPORARY(P8.15)`: it holds
the place of the single-spa shell and the microfrontends of Phase 8 until
they exist, and already talks to them through the browser event bus they
will use.

## 2. Business Value

AaaS exists to add two non-negative integers with a level of rigour no native
`+` operator can offer. `frontend-shell` contributes to that proposition as
described below.

Every capability of the platform would remain invisible without a way to
press `2`, `+`, `3` and `=`. This page is that way: it turns key presses into
calls of the public API in the right order, shows the progress of the
Peano computation while the user waits, and presents the result the ledger
has recorded. It delivers, with milestone M1 (P1.9), the first addition a
person can perform end to end.

## 3. Stakeholders

| Stakeholder | Interest |
| --- | --- |
| Customer Experience Tribe (CXT) | Owns, builds and operates the page; owns `expression-assembler` |
| End user of the calculator | Presses keys, sees the result |
| Transaction Integrity Office (TIO) | Owns `ledger`, which answers the task status until P3.3 |
| Platform Enablement Guild (PEG) | Gateway route `/` and the public API routes |
| Trust & Identity Board (TIB) | Login and rate limits of Phase 6 |

## 4. Scope

### In Scope

- Keypad `0`–`9`, `+`, `=`, `C` and a display (expression, status and
  progress while waiting, result, `Error`/`Unavailable`).
- Ordered key presses to `POST /api/v1/keys`, an `Idempotency-Key` per `=`,
  polling `GET /api/v1/tasks/{taskId}` every second.
- Browser events `aaas:key-pressed`, `aaas:clear`, `aaas:task-started`,
  `aaas:task-finished`.

### Out of Scope

- Any user-visible feature beyond the calculator keypad, display, timer and
  invoice download (CLAUDE.md section 1); here also the timer (P8.17) and
  the invoice button (P9.3).
- Login (P6.5), the official waiting time (stopwatch, P8.16).
- Access to the database of any other service (CLAUDE.md section 1, rule 4).

## 5. Key Performance Indicators

| KPI | Definition | Target | Source |
| --- | --- | --- | --- |
| Availability | Share of successful `GET /health` probes | 99.9% (SLO.md) | Compose health check, Prometheus |
| Time to result of 2 + 3 | From the click on `=` to `5` on the display | Reported; measured 1.2 s | Browser test (P1.9 automates it) |
| Delivered key presses | Key presses answered 204/202 | 100% while the API is up | Gateway access log |

## 6. Related Documents

[RACI](RACI.md) · [SLO](SLO.md) · [Runbook](RUNBOOK.md) ·
[Threat Model](THREAT_MODEL.md) · [Data Classification](DATA_CLASSIFICATION.md) ·
[Dependencies](DEPENDENCIES.md) · [Capacity](CAPACITY.md) · [API](API.md) ·
[Changelog](CHANGELOG.md) · [README](../README.md) ·
[ADR-0018](../../../docs/adr/0018-temporary-frontend-plain-javascript.md)
