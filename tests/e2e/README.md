# End-to-end tests

| Field | Value |
| --- | --- |
| Owning team | Customer Experience Tribe (CXT) |
| Tool | Playwright 1.64.1 (`@playwright/test`), headless Chromium |
| Image | `aaas/e2e:dev` from `mcr.microsoft.com/playwright:v1.64.1-noble` |
| Run | `make e2e` (`scripts/e2e.sh`) after `make up` |
| Version | 0.1.0 |

## Role

The end-to-end tests of `CLAUDE.md` 6.4: additions clicked in a real
browser on the calculator, through the gateway, with every service of the
flow behind it. `make e2e` must pass after every step that touches the
addition flow. The first case, `2 + 3 = 5`, is milestone **M1**.

## Cases

| Case | How | Since |
| --- | --- | --- |
| `2 + 3 = 5` (M1) | Browser: keys `2`, `Plus`, `3`, `Equals`; display `5` and `2+3 =` | P1.9 |
| `0 + 0 = 0`, `9 + 1 = 10`, `99999 + 1 = 100000` | Browser, one after another on the same page | P1.9 |
| `C` clears the expression | Browser | P1.9 |
| Idempotent `=` | Public API: the same `Idempotency-Key` twice returns the same task, recorded once with `result = 6` | P1.9 |
| Commutativity `3 + 5 == 5 + 3`, out-of-range operands, `99 + 1` | To be added with the validator and the commutator | P2.18 |

## Running

```sh
make up                      # the whole system
make e2e                     # all cases (about 15 s)
scripts/e2e.sh -g "2 \+ 3"   # one case (Playwright arguments are passed through)
open build/e2e/report/index.html
```

The tests run in a container on the Compose network `aaas-public` and open
`http://gateway:8000/` (`AAAS_E2E_NETWORK`, `AAAS_BASE_URL`); the host's
`127.0.0.1:80` is not reachable from containers. One worker, no retries:
additions share the ledger and the successor, and a flaky case is a defect.
The HTML report and, for failed cases, a screenshot and a trace are written
to `build/e2e/` (git-ignored).

## Files

| File | Content |
| --- | --- |
| `specs/addition.spec.js` | The cases |
| `lib/calculator.js` | Page object: keys by accessible name, display |
| `playwright.config.js` | Base URL, timeouts, reporters |
| `Dockerfile` | Test image |
| `package.json`, `package-lock.json` | Pinned test packages |

## Writing a case

Drive the page only through `lib/calculator.js` (accessible names `0`–`9`,
`Plus`, `Equals`, `Clear`; `#display-main`, `#display-detail`), so that the
cases keep working when the microfrontends of Phase 8 replace the
temporary page. Keep cases fast: an addition takes about 2.3 ms per unit of
the smaller operand.
