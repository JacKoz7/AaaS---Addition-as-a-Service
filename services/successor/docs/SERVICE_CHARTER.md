# Service Charter — `successor`

| Field | Value |
| --- | --- |
| Document | Service Charter |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Service Version | 0.1.0 |
| Last Reviewed | 2026-10-17 |
| Review Cadence | On every minor version of the service, and at least once per phase |

## 1. Mission

Computes n+1 through the digit services and carry.

The successor computes `S(n) = n + 1`, one step of Peano arithmetic, for
the task that asks for it; an addition `a + b` is `b` such steps (`CLAUDE.md`
1, rule 5; 3, step 7). Every call is logged in its CouchDB call log and
announced as `aaas.successor.called.v1`. Until P2.13 the step is computed
natively; from P2.13 through the digit services and `carry`.

## 2. Business Value

AaaS exists to add two non-negative integers with a level of rigour no native
`+` operator can offer. `successor` contributes to that proposition as
described below.

The successor is where the addition actually happens: it guarantees the
**correctness** of every step (`n + 1`, nothing else, only inside the range
of an addition) and the **traceability** of the whole computation: every
step of every addition is recorded once, with its task and trace, and
announced once on the event bus, even when the caller retries. Without it,
AaaS would have to fall back to the native `+`, a capitulation the
organisation is not prepared to make.

## 3. Stakeholders

| Stakeholder | Interest |
| --- | --- |
| Arithmetic Excellence Center (AEC) | Owns, builds and operates the service |
| End user of the calculator | Receives a correct result of the addition |

| Transaction Integrity Office (TIO) | Owns the callers: `ledger` (P1.7 until P3.3) and `saga-orchestrator` |
| Platform Enablement Guild (PEG) | Operates Redpanda, the bus of `aaas.successor.called.v1` |
| Observability Steering Group (OSG) | "Successor/s" dashboard (P7.3) |

## 4. Scope

### In Scope

- Serve `POST /v1/next` (`Next` of `CLAUDE.md` 4.3; gRPC from P2.1) for
  arguments `0..199997`.
- Log every call once in CouchDB, keyed by `<taskId>:<n>`.
- Publish `aaas.successor.called.v1` once per call, keyed by `taskId`, with
  the caller's trace continued.
- Answer retried calls with the original result and event.
- Serve `GET /health` and `GET /metrics`.

### Out of Scope

- Any user-visible feature beyond the calculator keypad, display, timer and
  invoice download (CLAUDE.md section 1).
- Access to the database of any other service (CLAUDE.md section 1, rule 4).

- The loop of `b` calls and continue-as-new (the ledger until P3.3, then
  the saga).
- The value and successor of a digit (`digit-0` … `digit-9`, from P2.13)
  and the carry (`carry`, from P2.13).
- Verifying the final sum (`consensus`, P4.5).

## 5. Key Performance Indicators

| KPI | Definition | Target | Source |
| --- | --- | --- | --- |
| Availability | Share of successful `GET /health` probes | See SLO.md | Prometheus |

| Successor calls per second | Rate of `computed` calls | Reported, not targeted; decides the waiting time of an addition | `successor_calls_total{outcome="computed"}` |
| Call latency | p50 and p99 of a served call | p99 below 50 ms (SLO.md) | `successor_call_duration_seconds` |
| Retried calls | Share of `replayed` calls | Reported; a high share points at caller timeouts | `successor_calls_total{outcome="replayed"}` |
| Dependency failures | Failed CouchDB or Kafka calls after retries | 0 in normal operation | `successor_dependency_failures_total{dependency}` |

## 6. Related Documents

[RACI](RACI.md) · [SLO](SLO.md) · [Runbook](RUNBOOK.md) ·
[Threat Model](THREAT_MODEL.md) · [Data Classification](DATA_CLASSIFICATION.md) ·
[Dependencies](DEPENDENCIES.md) · [Capacity](CAPACITY.md) · [API](API.md) ·
[Changelog](CHANGELOG.md) · [README](../README.md)
