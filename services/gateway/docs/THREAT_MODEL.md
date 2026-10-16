# Threat Model — `gateway`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `gateway` |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-16 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Networks: `public` (the only network with a published port: host
  `127.0.0.1:80` → container `8000`) and `services` (upstream services). No
  `data` network: the gateway has no database until P5.4.
- Trust boundaries crossed:
  1. Browser → gateway: untrusted input (paths, headers, bodies) on port 80.
  2. Gateway → upstream services on the `services` network:
     `expression-assembler` (`/api/v1/keys`), the task status owner
     (`/api/v1/tasks/{taskId}`, ledger until P3.3), `frontend-shell` (`/`).
  3. Operator → internal entry point 8080 (`/health`, `/metrics`): reachable
     only from the `services` network and inside the container, never
     published.
- The gateway consumes and produces no events.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A caller impersonates a user, or forges `X-Forwarded-*` / aliased headers (`X_Auth_User`) that upstreams trust | Header names that alias another header are deleted (`aliasHeadersStrategy: delete`); Traefik overwrites `X-Forwarded-*` from untrusted clients; JWT verification through forwardAuth to `rate-limiter` from P6.2 | Medium until P6.2 (no authentication yet), Low afterwards |
| Tampering | Ambiguous encoded paths (`%2F`, `%00`, `%5C`) route differently at the gateway and at the upstream (split view) | Every encoded reserved character is rejected with 400 at the entry point (`encodedCharacters`); routes match exact paths or a strict regular expression | Low |
| Repudiation | A request cannot be traced | JSON access log of every request (router, service, status, duration) with the `traceparent` and `Idempotency-Key` headers kept; other headers dropped from the log | Low; trace spans from P7.2 |
| Information Disclosure | An upstream error leaks internals (stack traces) to the user | Non-RFC 9457 error bodies are discarded and replaced by a problem document (`edge` plugin); the dashboard and API of Traefik are disabled; metrics are on the unpublished port | Low |
| Denial of Service | Floods of requests exhaust the gateway or reach the Peano machinery | `mem_limit` 64 MB and `cpus` 0.5; 2 s connection and header timeouts; limited retries (3 attempts, connection failures only); per-user limits through `rate-limiter` from P6.2; port bound to the loopback interface | Medium until P6.2, Low afterwards |
| Elevation of Privilege | A compromised Traefik process gains host access | Non-root user (UID 10001); unprivileged port 8000; read-only configuration in the image; the local plugin runs in Traefik's interpreter with the standard library only and is part of the image, never downloaded | Low |

Medium risks are covered by step P6.2 (authentication and rate limits) and
are not separately registered in `docs/governance/RISK_REGISTER.md`.
