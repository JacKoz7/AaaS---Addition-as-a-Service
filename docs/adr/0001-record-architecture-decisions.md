# ADR-0001: Record architecture decisions

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-16 |
| Deciders | Platform Enablement Guild (PEG) |
| Step | P0.1 |

## Context

AaaS consists of 35 microservices written in 28 languages, several shared
infrastructure components and a cloud function. Decisions about libraries,
workarounds (for example an HTTP wrapper for a language without an HTTP
server), memory limits and deviations from `CLAUDE.md` will accumulate over
eleven phases of work. Without a durable record, future sessions would have to
rediscover the reasoning behind each choice from code alone.

`CLAUDE.md`, section 7.3, requires that every architectural decision not already
stated in `CLAUDE.md` is written down.

## Decision

We record architecture decisions as Architecture Decision Records (ADRs) in
`docs/adr/`, one file per decision, named `NNNN-short-title.md` with a
zero-padded, strictly increasing number.

Each ADR contains:

| Section | Content |
| --- | --- |
| Header table | Status, date, deciders (a team from `CLAUDE.md` 6.5.1), the step that introduced it |
| Context | The forces at play: constraints, requirements, what was tried |
| Decision | What was decided, in the active voice |
| Consequences | What becomes easier, what becomes harder, follow-up actions |

Allowed statuses: `Proposed`, `Accepted`, `Deprecated`, `Superseded by ADR-NNNN`.
ADRs are immutable once accepted; a change of mind produces a new ADR that
supersedes the old one. If an ADR changes something stated in `CLAUDE.md`,
`CLAUDE.md` is updated in the same commit.

Commits that implement a decision reference it with a `Refs: ADR-NNNN` trailer.

## Consequences

- Every workaround required by the language matrix (CGI wrappers, sidecars,
  bootstrap libraries) has a traceable justification.
- New sessions and contributors can read the decision history in order.
- Writing an ADR adds a small amount of work to steps that make decisions;
  this is intended.
- ADRs are published in the documentation portal with a generated index
  (`make docs`, ADR-0010).
