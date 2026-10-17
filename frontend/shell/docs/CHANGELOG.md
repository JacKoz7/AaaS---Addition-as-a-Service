# Changelog — `frontend-shell`

All notable changes to this component are documented in this file. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the component is versioned with [Semantic Versioning](https://semver.org/)
under tags `frontend-shell/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `frontend-shell` by git-cliff
(`make changelog-shell VERSION=X.Y.Z`, ADR-0010) and then
completed by hand with a **Business Impact** section.

## [Unreleased]

## [0.1.0] — 2026-10-17

### Added

- Add the temporary calculator page (`33370cd`)

### Business Impact

We are delighted to unveil the first face of AaaS. Users may now press
`2`, `+`, `3` and `=` on a keypad of their very own and watch the display
report, step by step, the progress of the Peano computation behind it,
until the result recorded in the ledger appears: `5`, a little over one
second after the decisive press. Every key press reaches the platform in
the order it was made, every `=` is protected by its own idempotency key,
and the page already speaks the browser event bus on which the
microfrontends of Phase 8 will build. This interim experience is served
with a strict content security policy and a footprint of 7 MiB.
