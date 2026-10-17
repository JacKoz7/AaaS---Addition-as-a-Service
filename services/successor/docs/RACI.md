# RACI Matrix — `successor`

| Field | Value |
| --- | --- |
| Document | RACI Matrix |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

**R** Responsible (does the work) · **A** Accountable (one per activity,
signs off) · **C** Consulted (two-way, before the decision) · **I** Informed
(one-way, after the decision).

In practice every team is represented by the repository owner
(`@JacKoz7` in `CODEOWNERS`); the matrix records which organisational role
each decision belongs to.

| Activity | AEC | TIO | PEG | TIB | OSG |
| --- | --- | --- | --- | --- | --- |
| Code change within the service | R, A | I | I | I | I |
| Change of the arithmetic (P2.13) | R, A | C | I | I | I |
| Contract change (`Next`, `aaas.successor.called.v1`) | R, A | C | C | I | I |
| Deployment (`make up`, release tag) | R, A | I | C | I | I |
| Incident response | R, A | C | C | C | C |
| Database migration (CouchDB) | R, A | I | C | I | I |
| Security finding | R | I | I | A | I |
| Alert and dashboard change | R | I | I | I | A |
| Capacity (memory limit) change | R, A | I | C | I | C |

TIO owns the callers (`ledger`, `saga-orchestrator`); PEG operates Redpanda.

## Escalation Path

1. Arithmetic Excellence Center (AEC), service owner.
2. Platform Enablement Guild (PEG) for platform and infrastructure issues.
3. Repository owner (`@JacKoz7`).
