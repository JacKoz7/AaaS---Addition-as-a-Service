# RACI Matrix — `frontend-shell`

| Field | Value |
| --- | --- |
| Document | RACI Matrix |
| Component | `frontend-shell` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

**R** Responsible (does the work) · **A** Accountable (one per activity,
signs off) · **C** Consulted (two-way, before the decision) · **I** Informed
(one-way, after the decision).

In practice every team is represented by the repository owner
(`@JacKoz7` in `CODEOWNERS`); the matrix records which organisational role
each decision belongs to. TIO owns the task status API, PEG the gateway.

| Activity | CXT | TIO | PEG | TIB | OSG |
| --- | --- | --- | --- | --- | --- |
| Change of the page | R, A | I | I | I | I |
| Change of a used API contract | C | R, A (task status) | C | I | I |
| Deployment (`make up`, release tag) | R, A | I | C | I | I |
| Incident response | R, A | C | C | I | C |
| Security finding (CSP, headers) | R | I | C | A | I |
| Alert and dashboard change | R | I | I | I | A |
| Capacity (memory limit) change | R, A | I | C | I | C |

## Escalation Path

1. Customer Experience Tribe (CXT), owner of the page.
2. Transaction Integrity Office (TIO) for the task status, Platform
   Enablement Guild (PEG) for the gateway.
3. Repository owner (`@JacKoz7`).
