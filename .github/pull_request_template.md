<!--
Title: <type>(<scope>): <description>   (same format as a commit, CLAUDE.md 7.1)
-->

## Step

<!-- Step ID and the path of its log, e.g.
     P1.4 — docs/progress/steps/P1.4.md -->

## What Was Done

<!-- Concrete changes: services, files, contracts, configuration. -->

## How It Was Tested

<!-- Commands and their results. -->

## Definition of Done (CLAUDE.md 9.1)

- [ ] `make build` (or `make build-<service>`) passes
- [ ] Unit tests of the changed services pass
- [ ] `make up` starts everything expected at this stage; healthchecks are green
- [ ] `make e2e` passes (if the step touches the addition flow)
- [ ] `make lint` passes
- [ ] Service README and ADRs are up to date
- [ ] `make doc-coverage` shows 100% for changed services (headers, docstrings, `COMMENT ON`)
- [ ] All ten service documents exist and are true; `CHANGELOG.md`, `API.md`, `DEPENDENCIES.md`, `RUNBOOK.md`, `CAPACITY.md` updated where affected
- [ ] `make docs` builds the portal without warnings
- [ ] Commits follow Conventional Commits with a `Step:` trailer
- [ ] Everything in the repository is in English
- [ ] Step log and `docs/PROGRESS.md` updated (step-closing protocol, CLAUDE.md 8.1)
- [ ] No user-visible feature outside the scope of CLAUDE.md section 1
