# RACI Matrix — `gateway`

| Field | Value |
| --- | --- |
| Document | RACI Matrix |
| Component | `gateway` |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-16 |

**R** Responsible (does the work) · **A** Accountable (one per activity,
signs off) · **C** Consulted (two-way, before the decision) · **I** Informed
(one-way, after the decision).

In practice every team is represented by the repository owner
(`@JacKoz7` in `CODEOWNERS`); the matrix records which organisational role
each decision belongs to. CXT and TIO own the upstream services the gateway
routes to; TIB owns authentication and rate limiting attached in Phase 6.

| Activity | PEG | CXT | TIO | TIB | OSG |
| --- | --- | --- | --- | --- | --- |
| Code or configuration change within the service | R, A | I | I | I | I |
| New or changed route (public API, `CLAUDE.md` 4.1) | R, A | C | C | C | I |
| Contract change (`contracts/`) | R, A | C | C | I | I |
| Deployment (`make up`, release tag) | R, A | I | I | I | I |
| Incident response | R, A | C | C | C | C |
| Security finding | R | I | I | A | I |
| Alert and dashboard change | R | I | I | I | A |
| Capacity (memory limit) change | R, A | I | I | I | C |

The gateway has no database, so database migrations do not apply (Redis
arrives in P5.4 and the row is added then).

## Escalation Path

1. Platform Enablement Guild (PEG), service owner.
2. The team owning the failing upstream (CXT or TIO), when the gateway
   reports 502, 503 or 504 for its route.
3. Repository owner (`@JacKoz7`).
