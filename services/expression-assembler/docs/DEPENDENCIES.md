# Dependencies — `expression-assembler`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `expression-assembler` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Upstream (this service depends on)

Every request has a 1.8 s budget shared by all its calls (ADR-0014). Database
calls: 500 ms per attempt, up to three attempts with jitter, circuit breaker.
Kafka produce: 1 s per broker request, 1.5 s per message, idempotent producer
with `acks=all`. The service consumes no events, so there is no DLQ path; a
failed request is answered 503 and retried by the client.

| Dependency | Kind | Contract | Effect of Failure |
| --- | --- | --- | --- |
| `expression-assembler-db` (SurrealDB 3.3.4) | HTTP RPC on `data`, `AAAS_DB_URL` | Schema of `migrations/` | Every key press is answered 503; at startup the service retries migrations for 30 s, then exits 1 |
| `redpanda` (Kafka API) | TCP on `services`, `AAAS_KAFKA_BROKERS` | `contracts/events/aaas.key.pressed.v1.schema.json`, `contracts/events/aaas.expression.submitted.v1.schema.json` | Presses are stored but answered 503 until the broker is back; the retry publishes the stored event; health reports `broker: error` |
| `redpanda-topics` (one-shot job) | Compose `service_completed_successfully` | `contracts/events/topics.psv` | The service does not start until the topics exist |

`AAAS_BOOTSTRAP=platform` (config-server, OpenBao, Consul, schema registry)
arrives in Phase 5; the idempotency service replaces the local claim of
`Idempotency-Key` in P6.3.

## 2. Downstream (depends on this service)

| Dependant | Kind | Contract | Effect of Our Failure |
| --- | --- | --- | --- |
| `gateway` | HTTP, route `/api/v1/keys` | `POST /api/v1/keys` (`CLAUDE.md` 4.1) | The gateway answers 502/504 problems; no addition can start |
| Frontend (P1.8, Phase 8) | HTTP through the gateway | as above | The calculator cannot submit |
| `parser` (P1.5) | Event | `aaas.expression.submitted.v1` | No new additions are parsed |
| `stopwatch` (P8.16) | Event | `aaas.expression.submitted.v1` (`occurredAt` = start time) | No new timers start |
| Audit (no consumer yet) | Event | `aaas.key.pressed.v1` | Key press audit trail stops |
| Prometheus (P7.1) | HTTP scrape, port 8080 | `/metrics` | Metrics missing |

## 3. Build-Time and Runtime Dependencies

| Dependency | Version | Licence |
| --- | --- | --- |
| `mcr.microsoft.com/dotnet/sdk` (toolchain) | 10.0.402-noble | MIT |
| `mcr.microsoft.com/dotnet/aspnet` (runtime) | 10.0.13-alpine3.24 | MIT |
| Alpine package `cyrus-sasl` (librdkafka dependency) | 2.1.28-r9 | BSD-style (CMU) |
| `surrealdb/surrealdb` (database; binary also used by the tests) | v3.3.4 | Business Source License 1.1 (use permitted except offering SurrealDB as a commercial database service; each version becomes Apache-2.0 after four years) |
| Confluent.Kafka (with librdkafka.redist) | 2.16.0 | Apache-2.0 (librdkafka: BSD-2-Clause) |
| Microsoft.Extensions.Http.Resilience | 10.11.0 | MIT |
| OpenTelemetry.Extensions.Hosting, .Instrumentation.AspNetCore, .Exporter.OpenTelemetryProtocol | 1.20.0 | Apache-2.0 |
| prometheus-net.AspNetCore | 8.2.1 | MIT |
| StyleCop.Analyzers | 1.2.0-beta.556 | MIT |
| xunit.v3 | 4.0.2 | Apache-2.0 |
| Microsoft.AspNetCore.TestHost | 10.0.13 | MIT |
| JsonSchema.Net | 9.4.1 | MIT |
| docfx (API documentation) | 2.81.0 | MIT |
