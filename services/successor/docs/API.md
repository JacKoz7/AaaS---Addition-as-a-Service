<!-- GENERATED FILE: the events section is generated from contracts/events
     by `make api-md` (scripts/service-api.py) and checked by
     `make contracts-check`; the HTTP section is kept in sync by hand with
     CLAUDE.md 4.3 until the gRPC contract of P2.1 exists. Do not add content
     that is not in a contract. The native API documentation is published
     by `make docs`. -->
# API Reference — `successor`

| Field | Value |
| --- | --- |
| Document | API Reference |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Service Version | 0.1.0 |

## 1. HTTP (port 8080)

| Method | Path | Description | Response |
| --- | --- | --- | --- |
| `POST` | `/v1/next` | `Next` of `CLAUDE.md` 4.3 over HTTP/JSON until P2.1 (`TEMPORARY(P2.1)`): body `{ "n": <integer 0..199997>, "taskId": <lowercase UUID> }`, optional `traceparent` header | `200 { "n": n + 1 }`; `400` malformed body or non-integer `n`; `413` body above 4 KiB; `422` `n` outside the domain or malformed `taskId`; `503` CouchDB or Kafka unavailable (retry the call) |
| `GET` | `/health` | Liveness and readiness | `200 { "status": "ok", "checks": { "database": "ok", "broker": "ok" } }`, `503` when a check fails |
| `GET` | `/metrics` | Prometheus metrics (`successor_calls_total{outcome}`, `successor_call_duration_seconds`, `successor_dependency_failures_total{dependency}`, `successor_build_info`) | `200 text/plain; version=0.0.4` |

Errors use RFC 9457 (`application/problem+json`). Other paths answer `404`,
other methods on these paths `405`.

A call is idempotent per `(taskId, n)`: repeating it returns the same
result and publishes the same event (same `eventId`) again.

## 2. gRPC

None yet: `Next({n}) → {n}` on port 9090 arrives with the contracts of P2.1.

## 3. Events

<!-- BEGIN GENERATED: events (scripts/service-api.py, do not edit) -->
### `aaas.successor.called.v1` (produced)

One computation of n + 1 by the successor service.

- Producer: `successor`; partitions: 3; message key: `taskId`.
- Schema: [`aaas.successor.called.v1.schema.json`](../../../contracts/events/aaas.successor.called.v1.schema.json) (`urn:aaas:events:aaas.successor.called.v1`), in the envelope of `CLAUDE.md` 4.2.

| Payload field | Required | Description |
| --- | --- | --- |
| `n` | yes | Argument of the call: a natural number from 0 to 199 997, so that the result is a possible sum. |
| `result` | yes | The successor of n, always n + 1. |

<!-- END GENERATED: events -->
