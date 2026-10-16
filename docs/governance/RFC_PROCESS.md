# RFC Process

| Field | Value |
| --- | --- |
| Document | Request for Comments Process |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Last Reviewed | 2026-10-16 |

## 1. Purpose

A Request for Comments (RFC) is the formal instrument by which AaaS reaches
agreement on a change that affects more than one service. It ensures that
every team whose service participates in, or safeguards, the addition is
consulted before the change is made.

## 2. When an RFC Is Required

| Change | Instrument |
| --- | --- |
| Change confined to one service, no contract change | Commit(s) in a step |
| Architectural decision not covered by `CLAUDE.md` (library, workaround, limit) | ADR in `docs/adr/` |
| Change spanning two or more services, or a contract used by two or more services | **RFC** in `docs/rfc/`, followed by ADR(s) if decisions result |
| Incompatible event change | RFC plus a new topic version `.v<N+1>` (`CLAUDE.md` 4.2) |
| New user-visible feature | Not possible (`CLAUDE.md` section 1) |

## 3. Lifecycle

```
Draft -> In Review -> Accepted -> Implemented
                  \-> Rejected
                  \-> Withdrawn
```

| Status | Meaning |
| --- | --- |
| Draft | Author is writing; may change freely |
| In Review | Every affected team (see the RFC's "Affected Services") is Consulted per its RACI; minimum review period of one working day |
| Accepted | The accountable team signs off; the plan of steps is added to `docs/PROGRESS.md` |
| Implemented | All steps listed in the RFC are `DONE` |
| Rejected / Withdrawn | Kept for the record with the reason |

## 4. Procedure

1. Copy [`docs/rfc/TEMPLATE.md`](../rfc/TEMPLATE.md) to
   `docs/rfc/NNNN-short-title.md`, with `NNNN` the next free number.
2. Commit it as `docs(repo): propose RFC-NNNN <title>` within the current
   step.
3. Record review comments and their resolution in the "Discussion" section.
4. On acceptance, change the status, add the implementation steps to
   `docs/PROGRESS.md` (sub-steps if needed, `CLAUDE.md` 8.11) and reference
   `RFC-NNNN` in the `Refs:` trailer of the implementing commits.
5. Accepted RFCs are not edited afterwards; a later change needs a new RFC
   that supersedes the old one.
