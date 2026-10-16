# P<phase>.<step> — <Step title>

<!--
Step log template. Copy this file to docs/progress/steps/P<phase>.<step>.md
when a step starts (CLAUDE.md, section 8.1, "step start protocol"). Fill in
"Goal" and "Started" immediately; fill in the rest before the step is closed.
Everything in this file is written in English.
-->

| Field | Value |
| --- | --- |
| Status | IN_PROGRESS |
| Started | YYYY-MM-DD HH:MM CEST |
| Completed | |
| Branch | step/P<phase>.<step>-<short-description> |
| Commits | |
| Snapshot tag | |
| Depends on | P<phase>.<step>, ... |

## Goal
What this step has to deliver (copied from CLAUDE.md, section 9.3).

## What Was Done
Concrete list of changes: services, files, contracts, configuration.

## Verification
Every command that proves the Definition of Done, with its result:
- `make build-<service>` — passed / failed / not applicable (why)
- `make test-<service>` — N tests passed
- `make e2e` — passed / not applicable (why)
- `make lint` — passed
- `make doc-coverage` — 100%
- `make docs` — built without warnings

## Decisions
Decisions made during the step, with links to ADRs.

## Temporary Shortcuts
`TEMPORARY(...)` markers introduced, and the step that removes them.

## Notes for the Next Session
Anything the next session must know (gotchas, environment quirks, follow-ups).

## Checkpoints
(Filled only if the step was interrupted mid-way; see CLAUDE.md, section 8.1,
"interrupting a step".)

### Checkpoint N — YYYY-MM-DD HH:MM CEST
- Ready:
- Not working:
- Next actions:
  1.
