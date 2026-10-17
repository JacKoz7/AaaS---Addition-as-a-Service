# RACI Matrix — `expression-assembler`

| Field | Value |
| --- | --- |
| Document | RACI Matrix |
| Component | `expression-assembler` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

**R** Responsible (does the work) · **A** Accountable (one per activity,
signs off) · **C** Consulted (two-way, before the decision) · **I** Informed
(one-way, after the decision).

In practice every team is represented by the repository owner
(`@JacKoz7` in `CODEOWNERS`); the matrix records which organisational role
each decision belongs to. AEC consumes the expression event; PEG owns the
gateway route, the event contracts and Redpanda; TIB owns the idempotency
service that replaces the local key claim in P6.3.

| Activity | CXT | AEC | PEG | TIB | OSG |
| --- | --- | --- | --- | --- | --- |
| Code or configuration change within the service | R, A | I | I | I | I |
| Change of `POST /api/v1/keys` (public API, `CLAUDE.md` 4.1) | R, A | I | C | C | I |
| Event contract change (`aaas.key.pressed.v1`, `aaas.expression.submitted.v1`) | R | C | A | I | I |
| Database migration (`migrations/`) | R, A | I | I | I | I |
| Deployment (`make up`, release tag) | R, A | I | I | I | I |
| Incident response | R, A | C | C | I | C |
| Security finding | R | I | I | A | I |
| Alert and dashboard change | R | I | I | I | A |
| Capacity (memory limit) change | R, A | I | I | I | C |

## Escalation Path

1. Customer Experience Tribe (CXT), service owner.
2. Platform Enablement Guild (PEG), when Redpanda or the gateway is the cause.
3. Repository owner (`@JacKoz7`).
