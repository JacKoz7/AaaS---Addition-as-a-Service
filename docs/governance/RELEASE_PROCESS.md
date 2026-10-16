# Release Process

| Field | Value |
| --- | --- |
| Document | Release Process |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Last Reviewed | 2026-10-16 |

## 1. Versioning

| Artifact | Scheme | Tag | Example |
| --- | --- | --- | --- |
| Service or microfrontend | SemVer, independent per component | `<component>/vX.Y.Z` | `successor/v0.2.0` |
| Completed step (snapshot) | Step ID | `step/P<phase>.<step>` | `step/P1.4` |
| Completed phase (milestone) | Phase number | `phase-<N>-done` | `phase-1-done` |

SemVer per component: MAJOR for an incompatible contract change (which also
requires a new event topic version or gRPC package version), MINOR for a new
capability, PATCH for a fix. A new service starts at `0.1.0`.

## 2. Releasing a Component

1. All changes are on `main`, CI is green.
2. Update `services/<name>/docs/CHANGELOG.md`: `make changelog-<name>`
   previews the unreleased commits with scope `<name>`;
   `make changelog-<name> VERSION=X.Y.Z` inserts them as version `X.Y.Z`
   under `## [Unreleased]` (git-cliff, `cliff.toml`, ADR-0010). Then write
   the "Business Impact" section by hand. For a microfrontend the scope and
   tag prefix are `frontend-<name>`.
3. Update the version in the component's README and build metadata (OCI
   label `org.opencontainers.image.version`).
4. Commit `chore(<name>): release vX.Y.Z` with the `Step:` trailer of the
   current step.
5. Tag: `git tag -a <name>/vX.Y.Z -m "<name> vX.Y.Z"`; push with
   `git push --follow-tags`.

## 3. Closing a Phase

1. The last step of the phase is closed with the step-closing protocol
   (`CLAUDE.md` 8.1).
2. Write `docs/releases/phase-N.md`: a corporate announcement ("We are
   thrilled to announce...") whose list of changes is true and complete, with
   the milestone reached and the steps included.
3. Update "Milestones reached" in `docs/PROGRESS.md`.
4. Tag `phase-N-done` on `main` and push the tags.

## 4. Rollback

`main` history is never rewritten. A snapshot can be inspected with
`git checkout step/P<phase>.<step>`; reverting a closed step is done by a new
step or an ADR.
