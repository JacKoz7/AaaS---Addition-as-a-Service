# Threat Model — `frontend-shell`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `frontend-shell` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Network: `public` only; reached through the gateway on
  <http://127.0.0.1/> (loopback until Phase 12). No port is published by the
  container itself (CLAUDE.md 6.2).
- No data store. The code runs in the user's browser and calls the public
  API on the same origin.
- Trust boundaries crossed: browser → gateway (static files and the public
  API); the page trusts only answers of its own origin.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | Another page drives the calculator or reads results | `Content-Security-Policy` with `frame-ancestors 'none'`; same-origin API; no credentials until P6.5 | Low |
| Tampering | Injected script changes what the display shows | CSP `script-src 'self'`, no inline script, no third-party code; the display writes `textContent` only, never HTML | Low |
| Tampering | Modified static files in the image | Files copied at build time into a read-only image layer; nginx runs as UID 101 | Low |
| Repudiation | A key press cannot be traced | JSON access log of nginx; each key press carries `sessionId` and `seq`, logged by `expression-assembler` | Low |
| Information Disclosure | `/health` or `/metrics` reachable from outside | Both answer 404 to requests that came through the gateway (`X-Forwarded-For`); `server_tokens off` | Low |
| Information Disclosure | Referrer leaks the URL to other sites | `Referrer-Policy: no-referrer`; the page links nowhere | Low |
| Denial of Service | A user floods the API with key presses | Rate limits at the gateway (P6.2); the page sends keys one at a time | Medium until P6.2 |
| Elevation of Privilege | Compromised nginx gains host access | Unprivileged nginx image, UID 101, no shell use at runtime | Low |

No High risk.
