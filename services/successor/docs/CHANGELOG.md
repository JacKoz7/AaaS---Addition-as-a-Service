# Changelog — `successor`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `successor/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `successor` by git-cliff
(`make changelog-successor VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [Unreleased]

## [0.1.0] — 2026-10-17

### Added

- Compute the successor and log every call (`ec498e6`)

### Business Impact

We are delighted to announce that AaaS can now count. The successor service,
crafted in Haskell, takes any natural number from 0 to 199 997 and returns,
with unwavering conviction, the next one. Every single step is recorded in
a dedicated CouchDB call log under its own task and argument, and announced
to the organisation as `aaas.successor.called.v1`, only after the event bus
has confirmed receipt. Should a caller lose patience and ask again, it is
served the very same answer and the very same event, so that no step of an
addition is ever counted twice. A step takes 2 milliseconds at the median,
bringing the full experience of Peano arithmetic within reach of every user.
