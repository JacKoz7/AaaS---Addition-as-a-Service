# Changelog — `ledger`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `ledger/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `ledger` by git-cliff
(`make changelog-ledger VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [Unreleased]

## [0.1.0] — 2026-10-17

### Added

- Record every result in a hash chain in immudb (`6f81f6c`)

### Business Impact

We are proud to announce that AaaS now keeps a permanent record of its
achievements. Every addition requested of the platform is counted, one
successor call at a time, and its result is entered into an immutable,
hash-chained ledger in immudb, in which altering any recorded addition
would break every entry that follows it. Each entry is announced to the
organisation as `aaas.ledger.appended.v1` only once the event bus has
confirmed receipt, and the progress of every addition can be followed live
through `GET /api/v1/tasks/{taskId}`. The ledger survives its own restarts,
those of its database and those of the successor without counting or
recording anything twice, and it resumes a large addition from its last
checkpoint rather than from the beginning. `2 + 3` is recorded in under a
second, `1000 + 1000` in 2.3 seconds: a decisive step towards the
organisation's first end-to-end addition.
