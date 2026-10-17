# Data Classification — `frontend-shell`

| Field | Value |
| --- | --- |
| Document | Data Classification |
| Component | `frontend-shell` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Classification Levels

| Level | Meaning |
| --- | --- |
| PUBLIC | May be shown to anyone (for example the result of 2 + 3) |
| INTERNAL | Operational data of AaaS; not shown to users |
| CONFIDENTIAL | Credentials, tokens and identifiers linkable to a person |

## 2. Data Inventory

Store: none. The page keeps its state in browser memory only; nothing is
written to cookies, `localStorage` or the server's disk by this component.

| Data Item | Location | Classification | Retention | Personal Data |
| --- | --- | --- | --- | --- |
| Expression, status, progress, result | Browser memory, display | PUBLIC | Until the next calculation or a reload | No |
| Session identifier (random UUID per calculation) | Browser memory; sent to `expression-assembler` | INTERNAL | Until `C`, the next calculation or a reload | Yes, pseudonymous (docs/governance/DPIA.md) |
| `Idempotency-Key` of `=` | Browser memory; sent with `=` | INTERNAL | Same | No |
| Task identifier | Browser memory; URL of the status requests | INTERNAL | Same | No |
| nginx access log (method, path, status, size, duration) | Container stdout | INTERNAL | Docker log rotation | No (client addresses are not logged) |

## 3. Handling Rules

- Data is never read by another service directly (CLAUDE.md section 1,
  rule 4); the page only uses the public API.
- CONFIDENTIAL values: none are handled before login (P6.5).
- Restarting the container erases nothing that matters: the page is static.
