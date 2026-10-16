# Changelog — `gateway`

All notable changes to this service are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
service is versioned with [Semantic Versioning](https://semver.org/) under
tags `gateway/vX.Y.Z` (docs/governance/RELEASE_PROCESS.md).

Entries are generated from commits with scope `gateway` by git-cliff
(`make changelog-gateway VERSION=X.Y.Z`, ADR-0010) and then completed by
hand with a **Business Impact** section.

## [Unreleased]

## [0.1.0] — 2026-10-16

### Added

- Route the public api and the frontend through traefik (`16719d1`)

### Business Impact

We are proud to open the front door of AaaS. From this release on, every
key press, every task status request and the calculator itself reach the
platform through one address, host port 80, and every error a user can meet
on the API speaks the same language: RFC 9457 problem details. The routes
for `expression-assembler`, the task status owner and the frontend are in
place ahead of the services themselves, so each of them is reachable the
moment its step delivers it; until then the gateway reports their absence
precisely and politely.
