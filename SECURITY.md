# Security Policy

| Field | Value |
| --- | --- |
| Document | Security Policy |
| Owning Team | Trust & Identity Board (TIB) |
| Classification | INTERNAL |
| Last Reviewed | 2026-10-16 |

AaaS adds two integers. The Trust & Identity Board nevertheless treats every
weakness that could make an addition wrong, unavailable or attributable to the
wrong user as a security issue of the highest institutional significance.

## Supported Versions

Only the current state of `main` is supported. Each service is versioned
independently (`<service>/vX.Y.Z`, see
[`docs/governance/RELEASE_PROCESS.md`](docs/governance/RELEASE_PROCESS.md));
fixes are made on `main` and no older version receives backports.

## Scope

In scope:

- Any service under `services/`, any microfrontend under `frontend/`, the
  Compose files under `compose/` and the configuration under `infra/`.
- Incorrect results of an addition, bypass of authentication or rate limits,
  tampering with the ledger hash chain, disclosure of credentials or session
  identifiers, and any path that creates AWS cost (`CLAUDE.md` section 10).

Out of scope:

- Findings that require an attacker to already control the host running
  Docker Compose.
- The waiting time of large additions; it is a feature (`CLAUDE.md`
  section 1).
- Findings in third-party images that are fixed upstream; report those
  upstream and open an issue here asking for a version bump.

## Reporting a Vulnerability

Report vulnerabilities **privately** through GitHub private vulnerability
reporting: [Report a vulnerability](https://github.com/JacKoz7/AaaS---Addition-as-a-Service/security/advisories/new) (repository tab **Security** →
**Report a vulnerability**). The report is visible only to the maintainers.

Do not open a public issue for a vulnerability, and do not include working
credentials or tokens in any report. Incidents without a security aspect
(outages, failed additions) use the public **Incident report** issue form.

## Handling

| Stage | Target |
| --- | --- |
| Acknowledgement | 3 working days |
| Triage and severity (Critical, High, Medium, Low) | 7 working days |
| Fix on `main` for Critical and High | 30 days |
| Entry in `docs/governance/RISK_REGISTER.md` | When the fix is not immediate |

Fixes are released with a `fix(<service>)` commit and recorded in the
service's `CHANGELOG.md`. Incidents caused by a vulnerability are followed by
a blameless postmortem
([`docs/governance/INCIDENT_POSTMORTEM_TEMPLATE.md`](docs/governance/INCIDENT_POSTMORTEM_TEMPLATE.md)).

## Secrets

No secret is ever committed. `.env` is git-ignored and only `.env.example`
with placeholder values is versioned; the `detect-private-key` pre-commit
hook blocks private keys. Database credentials move to OpenBao in step P5.3.
A secret committed by mistake is treated as compromised: rotate it, then
remove it from history with the repository owner's approval.
