# Data Classification — `gateway`

| Field | Value |
| --- | --- |
| Document | Data Classification |
| Component | `gateway` |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-16 |

## 1. Classification Levels

| Level | Meaning |
| --- | --- |
| PUBLIC | May be shown to anyone (for example the result of 2 + 3) |
| INTERNAL | Operational data of AaaS; not shown to users |
| CONFIDENTIAL | Credentials, tokens and identifiers linkable to a person |

## 2. Data Inventory

Store: none. The gateway keeps no state; the Redis route table follows in
P5.4. Data passes through the gateway and appears only in its logs.

| Data Item | Location | Classification | Retention | Personal Data |
| --- | --- | --- | --- | --- |
| Request path and method (including `taskId` in `/api/v1/tasks/{taskId}`) | Access log (stdout) | INTERNAL | Docker log retention of the host; Loki from P7.1 | No (a task identifier is not linkable to a person without the session) |
| Client address and port | Access log | INTERNAL | As above | Pseudonymous on a single host (always the Docker bridge address); personal data once public access exists (Phase 12, see DPIA) |
| `traceparent` and `Idempotency-Key` headers | Access log | INTERNAL | As above | No |
| All other request headers (including `Authorization` from P6.1 and cookies) | Not logged (`defaultMode: drop`) | CONFIDENTIAL | Not stored | — |
| Request and response bodies (`sessionId`, keys, results) | Not logged; streamed through | — | Not stored | — |
| Prometheus metrics (counters per router, service and status) | `/metrics`, port 8080 | INTERNAL | Prometheus retention from P7.1 | No |

## 3. Handling Rules

- Data is never read by another service directly (`CLAUDE.md` section 1,
  rule 4); other services obtain it through the contracts in API.md.
- CONFIDENTIAL values are never written to logs: the access log keeps only
  the two headers listed above.
- The gateway stores nothing on disk; removing the container erases nothing
  but its log buffer.
