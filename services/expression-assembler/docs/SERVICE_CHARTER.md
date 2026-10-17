# Service Charter — `expression-assembler`

| Field | Value |
| --- | --- |
| Document | Service Charter |
| Component | `expression-assembler` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Service Version | 0.1.0 |
| Last Reviewed | 2026-10-17 |
| Review Cadence | On every minor version of the service, and at least once per phase |

## 1. Mission

`expression-assembler` turns the clicks of the calculator into additions.
It records every key press of a session exactly once, and when the user
presses `=` it assembles the expression typed since the last `C` or `=`,
opens a task with a time-ordered identifier and hands the expression to the
rest of AaaS through `aaas.expression.submitted.v1`.

## 2. Business Value

AaaS exists to add two non-negative integers with a rigour no native `+`
operator can offer. That rigour starts at the first click. This service
guarantees that a user who presses `=` once gets exactly one addition, even
when the network repeats the request, the browser retries or two retries
race each other; that nothing is announced to the platform that is not
already stored; and that the official waiting time starts at the instant of
the `=` press (the `occurredAt` of the expression event, used by the
stopwatch from P8.16). Without it, the 34 services behind it would have
nothing to compute.

## 3. Stakeholders

| Stakeholder | Interest |
| --- | --- |
| Customer Experience Tribe (CXT) | Owns, builds and operates the service; owns the frontend that calls it |
| End user of the calculator | Every click is accepted quickly; `=` returns a task to watch |
| Arithmetic Excellence Center (AEC) | `parser` consumes `aaas.expression.submitted.v1` (P1.5) |
| Platform Enablement Guild (PEG) | Routes `/api/v1/keys` through the gateway; owns the event contracts and Redpanda |
| Trust & Identity Board (TIB) | Rate limiting (P6.2) and the idempotency service (P6.3) that replaces the local key claim |
| Observability Steering Group (OSG) | Consumes metrics, logs and traces (Phase 7) |

## 4. Scope

### In Scope

- `POST /api/v1/keys`: validation, idempotent recording of key presses per
  `(sessionId, seq)`, publication of `aaas.key.pressed.v1`.
- On `=`: `Idempotency-Key` handling, expression assembly, task creation
  (UUIDv7), publication of `aaas.expression.submitted.v1`, `202 { taskId }`.
- Storage of key presses, tasks and claimed idempotency keys in its own
  SurrealDB instance, with versioned migrations applied at startup.
- `GET /health`, `GET /metrics`, structured JSON logs, trace context
  propagation into events.

### Out of Scope

- Any user-visible feature beyond the calculator (`CLAUDE.md` section 1),
  in particular calculation history: stored presses are never shown.
- Parsing, range checks and the addition itself (parser, validator and the
  services behind them).
- Authentication and rate limiting (`auth` P6.1, `rate-limiter` P6.2 in
  front of the gateway).
- The idempotency service (P6.3); until then the claim of an
  `Idempotency-Key` is local to this service (`TEMPORARY(P6.3)`).
- Task status (`GET /api/v1/tasks/{taskId}`, ledger until P3.3, then the
  saga) and the timer (stopwatch).

## 5. Key Performance Indicators

| KPI | Definition | Target | Source |
| --- | --- | --- | --- |
| Availability | Share of successful `GET /health` probes | See SLO.md | Compose health check; Prometheus from P7.1 |
| Key press latency | p99 of `http_request_duration_seconds` for `POST /api/v1/keys` | < 100 ms | prometheus-net HTTP metrics |
| Duplicate tasks | Tasks created per distinct `Idempotency-Key` | exactly 1 | `expression_assembler_tasks_submitted_total` versus distinct keys; tests |
| Dependency rejections | `expression_assembler_rejected_total` with reason `database`, `broker` or `deadline` / all requests | < 0.1% while dependencies are healthy | Service metrics |

## 6. Related Documents

[RACI](RACI.md) · [SLO](SLO.md) · [Runbook](RUNBOOK.md) ·
[Threat Model](THREAT_MODEL.md) · [Data Classification](DATA_CLASSIFICATION.md) ·
[Dependencies](DEPENDENCIES.md) · [Capacity](CAPACITY.md) · [API](API.md) ·
[Changelog](CHANGELOG.md) · [README](../README.md) ·
[ADR-0014](../../../docs/adr/0014-expression-assembler-surrealdb-and-kafka.md)
