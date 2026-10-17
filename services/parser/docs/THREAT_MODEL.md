# Threat Model — `parser`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `parser` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Network: `services` only (Redpanda). The database is an embedded SQLite
  file, so the service has no `data` network and no credentials. No port is
  published on the host (CLAUDE.md 6.2); the gateway has no route to it.
- Data store: SQLite (embedded) in the volume `parser-data`, reachable only
  by this process.
- Trust boundaries: messages consumed from `aaas.expression.submitted.v1`
  (written by `expression-assembler`, but any container on `services` can
  produce while Redpanda has no authentication); messages produced to
  `aaas.addition.requested.v1`; `GET /health` and `GET /metrics` reachable
  from the `services` network.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on `services` produces forged `aaas.expression.submitted.v1` events | Network segmentation; strict decoding (type, version, identifiers); discarded messages are logged and counted | Medium until broker authentication; Low impact because a forged event can only request an addition |
| Tampering | A consumed expression is crafted to break the parser (very long input, unexpected bytes) | Byte-wise lexer with a closed alphabet; numerals kept as text, so no integer overflow; operand range enforced before publishing; schema limits the expression to 64 characters | Low |
| Tampering | The SQLite file is altered to change a cached AST | Volume reachable only by this container; a cache entry that does not decode counts as a miss; the AST is re-checked by `Operands` before publishing | Low |
| Repudiation | A request cannot be traced to its expression | One log line per consumed event with `taskId`, `traceId`, `spanId` and outcome; `processed_events` keeps the outcome per `eventId` | Low |
| Information Disclosure | Session identifiers leak through logs | The parser logs `taskId`, never `sessionId`; the database stores no session identifier | Low |
| Denial of Service | A flood of events or a stuck message stalls the consumer | Sequential processing with bounded memory (64 MB limit); `consumer` health check fails after 15 s; rate limits at the gateway (P6.2) | Medium until the dead-letter service (P3.6) removes stuck messages |
| Denial of Service | A second instance doubles every request | Single instance by design (ADR-0015, R-013) | Low |
| Elevation of Privilege | A compromised process gains host access | Non-root user (UID 10001), Alpine runtime with only the needed libraries, no shell tools beyond busybox | Low |
