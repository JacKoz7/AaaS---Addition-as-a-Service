# Threat Model — `successor`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Networks: `services` (callers, Redpanda) and `data` (its own CouchDB
  only). No port is published on the host (CLAUDE.md 6.2) and the gateway
  has no route to the service.
- Data store: CouchDB (`successor-db`), reachable only on `data` with the
  service's credentials.
- Trust boundaries: `POST /v1/next` from any container on `services` (no
  authentication between services yet); messages produced to
  `aaas.successor.called.v1`; CouchDB on `data`.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on `services` calls `POST /v1/next` for a task it does not own and pollutes the call log | Network segmentation; strict validation of `taskId` and `n`; a forged call cannot change the result of another call (the natural key returns the stored document) | Medium until service authentication; Low impact |
| Tampering | The call log is altered to change a stored result | CouchDB only on `data` with credentials; a stored result that differs from `n + 1` is refused with 503 instead of being replayed; the consensus vote (P4.5) checks the sum | Low |
| Tampering | A large or crafted body exhausts the parser | Bodies above 4 KiB are refused (413); JSON parsed with aeson; integers checked before any side effect | Low |
| Repudiation | A call cannot be traced to a task | Every call is a document with `taskId`, `traceId` and `calledAt`, and an event with the trace continued | Low |
| Information Disclosure | CouchDB credentials leak | Password only in the environment (OpenBao from P5.3), never logged; problems carry no internal details | Low |
| Denial of Service | A flood of calls exhausts CouchDB or the disk | `mem_limit` and `cpus`; rate limits at the gateway (P6.2) protect the user side; storage growth tracked as R-014 | Medium |
| Elevation of Privilege | A compromised process gains host access | Non-root user (UID 10001), Debian slim runtime with four packages | Low |
