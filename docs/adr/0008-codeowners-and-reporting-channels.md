# ADR-0008: Code owner identity and reporting channels

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-16 |
| Deciders | Platform Enablement Guild (PEG), Trust & Identity Board (TIB) |
| Step | P0.8 |

## Context

`CLAUDE.md` 6.5.1 and 6.5.6 say that every team is, in practice, the
repository owner, written as `@aaas-owner` in `CODEOWNERS`. GitHub validates
`CODEOWNERS`: an owner that is not an existing account or team is reported
as an error and never requested for review. No account `aaas-owner` exists;
the repository belongs to the personal account `JacKoz7`, which cannot have
GitHub teams.

`SECURITY.md` and `CODE_OF_CONDUCT.md` need a private reporting channel.
GitHub private vulnerability reporting is available only for public
repositories, and this repository is private.

## Decision

- `CODEOWNERS` assigns every path to `@JacKoz7`. Each block of paths is
  preceded by a comment naming the team of `CLAUDE.md` 6.5.1 that owns it,
  so the organisational mapping stays visible. `CLAUDE.md` and the RACI
  template are updated to name `@JacKoz7`.
- While the repository is private, vulnerabilities are reported through an
  issue (the incident form) with the `[Security]` title prefix, and Code of
  Conduct reports through an issue prefixed `[Code of Conduct]` or privately
  to the owner; issues of a private repository are visible only to its
  collaborators.
- Before the repository is made public (Phase 12), GitHub private
  vulnerability reporting is enabled and `SECURITY.md` and
  `CODE_OF_CONDUCT.md` are switched to it.

## Consequences

- GitHub accepts `CODEOWNERS` and requests the owner's review on pull
  requests.
- If the repository moves to an organisation, the blocks can be reassigned
  to real GitHub teams named after the eight AaaS teams without changing the
  structure of the file.
