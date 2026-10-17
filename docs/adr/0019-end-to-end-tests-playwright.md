# ADR-0019: End-to-end tests with Playwright in a container on the public network

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-17 |
| Deciders | Customer Experience Tribe (CXT), Platform Enablement Guild (PEG) |
| Step | P1.9 |

## Context

`CLAUDE.md` 6.4 requires `make e2e` with end-to-end cases through the
gateway (`2+3=5`, `0+0=0`, `9+1=10`, `99999+1=100000`, commutativity,
idempotency of `=`) and step P1.9 allows "Playwright or an HTTP script".
Milestone M1 is "`2+3=5` goes through the gateway and the frontend shows the
result", which only a browser can show. Nothing may be required on the host
besides Docker. The gateway publishes port 80 on the host's loopback only.

## Decision

- **Playwright in a browser**, not an HTTP script: the cases click the keys
  of the calculator in headless Chromium and read the display, so the page
  (P1.8) is part of what is tested. One API-level case covers what the page
  cannot show (the same `Idempotency-Key` returns the same task).
- **Container on `aaas-public`.** `scripts/e2e.sh` builds `aaas/e2e:dev`
  from `mcr.microsoft.com/playwright:v1.64.1-noble` with the exact packages
  of `package-lock.json` (`@playwright/test` 1.64.1, matching the browsers of
  the image), checks that the gateway is healthy, and runs the tests on the
  Compose network against `http://gateway:8000/`; containers cannot reach
  the host's `127.0.0.1:80`. Results go to `build/e2e/`.
- **Page object by accessible names** (`Plus`, `Equals`, `Clear`, digits)
  and display ids, so that the specs survive the microfrontends of Phase 8.
- **One worker, no retries**: every addition shares the ledger and the
  successor; a flaky case is a defect.
- **Cases now**: `2+3=5` (M1), `0+0`, `9+1`, `99999+1` (one successor call
  without the commutator), `C`, idempotent `=`. Commutativity and range
  errors need the commutator (P2.15) and the validator (P2.14) and are added
  by P2.18; `1+99999` would take 99 999 calls (about 4 minutes) until the
  commutator swaps the operands.
- **Not in CI yet.** The CI matrix builds and tests changed components; an
  end-to-end run needs every image of the system built and started, which on
  a hosted runner rebuilds every toolchain (about 30 minutes for Haskell
  alone). `make e2e` is part of the local Definition of Done.
- **Documentation**: the test files carry the file header and JSDoc blocks
  with the fields of 6.5.3; `tests/e2e` is not a component, so no linter
  enforces them (doc-check enforces the headers).

## Consequences

- `make e2e` runs the four cases in about 15 s and fails with the
  Playwright report, a screenshot and a trace when the result does not
  appear (checked with the ledger stopped); it exits 2 without a healthy
  gateway.
- The Playwright base image takes 3.5 GB of disk; it is a third-party base
  image and is not removed by `make prune-stages`.
- Every step that touches the flow runs `make e2e` (`CLAUDE.md` 6.4).
