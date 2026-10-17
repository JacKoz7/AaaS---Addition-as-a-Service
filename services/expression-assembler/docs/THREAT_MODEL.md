# Threat Model — `expression-assembler`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `expression-assembler` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Networks: `services` (reached by the gateway; reaches Redpanda) and `data`
  (reaches its own database only). No published port.
- Trust boundaries crossed:
  1. Gateway → service: untrusted user input (`sessionId`, `key`, `seq`,
     `Idempotency-Key`, `traceparent`) on `POST /api/v1/keys`.
  2. Service → `expression-assembler-db` (SurrealDB) on the `data` network,
     authenticated with a password from the environment and a session token.
  3. Service → Redpanda on the `services` network (Kafka API, no
     authentication on the single-host broker, ADR-0011).
- Data produced: `aaas.key.pressed.v1`, `aaas.expression.submitted.v1`.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A caller submits presses for another user's session | Session identifiers are random UUIDs known only to the browser that created them; JWT authentication and per-user limits in front of the gateway from P6.1/P6.2 | Medium until P6.2, Low afterwards |
| Tampering | Injection into SurrealQL through `sessionId`, `key` or `Idempotency-Key` | Values are passed as typed RPC variables, never concatenated; inputs are validated (UUID, key set, key pattern); namespace and database names are checked identifiers; schemafull tables with `ASSERT` on keys | Low |
| Tampering | A forged event on the bus impersonates the service | The broker is reachable only on the internal network; producers are fixed by the contracts and validated by the schema registry from P3.1 | Low on a single host |
| Repudiation | A task cannot be traced to its presses | Every press and task is stored with its `traceparent`; the task links to its `=` press; logs carry `taskId` and trace identifiers | Low |
| Information Disclosure | Error details reveal internal hosts or stack traces | 503 problems carry generic details; causes are logged only; unhandled exceptions are not rendered | Low |
| Information Disclosure | Session identifiers and typed numbers leak from storage | No published database port; database only on `data`; password from the environment (OpenBao from P5.3); data classified INTERNAL (DATA_CLASSIFICATION.md) | Low |
| Denial of Service | Floods of presses fill the database or exhaust memory | 4 KiB body limit; 1.8 s request budget; `mem_limit` 128 MB (service) and 256 MB (database, bounded SurrealKV caches); per-user limits from P6.2 | Medium until P6.2 (no retention job yet; storage grows with every press) |
| Denial of Service | A broker outage leaves stored events unpublished | 503 to the client, which retries and republishes the stored event; no background republisher in 0.1.0 | Medium: a client that never retries leaves its last press unpublished (audit only for presses; for `=` the user retries to get a task) |
| Elevation of Privilege | A compromised process gains host or database-wide access | Non-root user (UID 10001); the database runs as `nonroot`; the database user is root only of this dedicated instance | Low |

Medium risks are covered by P6.2 (authentication, limits) and by the saga
outbox of P3.4 (reliable publication for the computation path); they are not
separately registered in `docs/governance/RISK_REGISTER.md`.
