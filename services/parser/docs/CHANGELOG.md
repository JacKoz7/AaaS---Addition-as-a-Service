# Changelog — `parser`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `parser/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `parser` by git-cliff
(`make changelog-parser VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [Unreleased]

## [0.1.0] — 2026-10-17

### Added

- Parse submitted expressions and request additions (`509a4b7`)

### Business Impact

We are proud to announce that AaaS now understands what it is asked. Every
expression submitted with `=` is read by a dedicated OCaml service, held to
the uncompromising grammar `number + number`, and, if it passes, handed to
the computation as `aaas.addition.requested.v1`, exactly once, however many
times the event bus chooses to deliver it. Expressions that fall short, from
the ambitious `2++3` to the minimalist `+`, are declined with a precise
reason and position, recorded for posterity and counted on our metrics.
Repeated expressions are served from an AST cache, and a typical addition
request leaves the parser a mere 13 milliseconds (median) after `=` was
pressed.
