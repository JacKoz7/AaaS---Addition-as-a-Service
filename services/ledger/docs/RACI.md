# RACI Matrix — `ledger`

| Field | Value |
| --- | --- |
| Document | RACI Matrix |
| Component | `ledger` |
| Owning Team | Transaction Integrity Office (TIO) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

**R** Responsible (does the work) · **A** Accountable (one per activity,
signs off) · **C** Consulted (two-way, before the decision) · **I** Informed
(one-way, after the decision).

In practice every team is represented by the repository owner
(`@JacKoz7` in `CODEOWNERS`); the matrix records which organisational role
each decision belongs to. AEC owns the producer of the consumed event and
the successor; CXT, ROU and CGC own the consumers of the announcement.

| Activity | TIO | AEC | CXT | ROU | CGC | PEG | TIB | OSG |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Code change within the service | R, A | I | I | I | I | I | I | I |
| Contract change (`contracts/`, hash rule) | R, A | C | C | C | C | C | I | I |
| Deployment (`make up`, release tag) | R, A | I | I | I | I | C | I | I |
| Incident response | R, A | C | I | I | I | C | C | C |
| Database migration | R, A | I | I | I | I | C | I | I |
| Security finding | R | I | I | I | I | I | A | I |
| Alert and dashboard change | R | I | I | I | I | I | I | A |
| Capacity (memory limit) change | R, A | I | I | I | I | C | I | C |

## Escalation Path

1. Transaction Integrity Office (TIO), service owner.
2. Arithmetic Excellence Center (AEC) when the successor or the parser is
   involved; Platform Enablement Guild (PEG) for Redpanda and the gateway.
3. Repository owner (`@JacKoz7`).
