# Changelog — `expression-assembler`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `expression-assembler/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `expression-assembler` by git-cliff
(`make changelog-expression-assembler VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [Unreleased]

## [0.1.0] — 2026-10-17

### Added

- Record key presses and submit expressions (`01c5b9b`)

### Business Impact

We are delighted to announce that AaaS now listens. From this release on,
every click of the calculator reaches the platform through
`POST /api/v1/keys`, is recorded exactly once in our dedicated SurrealDB
instance and is announced on the event bus as `aaas.key.pressed.v1`. Pressing
`=` turns the digits and `+` typed since the last `C` or `=` into a task with
a time-ordered identifier and publishes `aaas.expression.submitted.v1`: the
very first event of every future addition. One `Idempotency-Key`, one task,
however often the network repeats the request; nothing is announced that is
not already stored; and an unavailable dependency is reported within 1.8
seconds as a polite RFC 9457 problem, so that the user may simply try again.
A key press is acknowledged in about 11 milliseconds, leaving the full
waiting experience to the Peano arithmetic further down the line.
