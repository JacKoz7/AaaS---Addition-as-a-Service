# Dependencies — `frontend-shell`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `frontend-shell` |
| Owning Team | Customer Experience Tribe (CXT) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-17 |

## 1. Upstream (this component depends on)

| Dependency | Kind | Contract | Effect of Failure |
| --- | --- | --- | --- |
| Gateway (PEG) | Routes `/` to this container and `/api/*` to the services | services/gateway/config/dynamic/routes.yml | The page cannot be loaded (502) |
| `expression-assembler` (CXT) | `POST /api/v1/keys` (from the browser) | services/expression-assembler/README.md | `Unavailable` after 3 attempts of 2 s; the user presses `C` and retries |
| `ledger` (TIO), `TEMPORARY(P3.3)` | `GET /api/v1/tasks/{taskId}` (from the browser) | services/ledger/docs/API.md | The display keeps waiting; polling continues every second |

## 2. Downstream (depends on this component)

| Dependant | Kind | Contract | Effect of Our Failure |
| --- | --- | --- | --- |
| End user | Browser | The page | No addition can be started |
| `tests/e2e` (P1.9) | Browser test | The page and its button labels (`Plus`, `Equals`, `Clear`) | The end-to-end test fails |

## 3. Build-Time Dependencies

| Dependency | Version | Licence |
| --- | --- | --- |
| `nginxinc/nginx-unprivileged` (runtime image) | 1.30.6-alpine3.24 | BSD-2-Clause (nginx), various open-source (Alpine) |
| `node` (toolchain image) | 24.22.0-alpine3.24 | MIT (Node.js) |
| eslint, @eslint/js | 10.13.0, 10.0.1 | MIT |
| eslint-plugin-jsdoc | 65.3.11 | BSD-3-Clause |
| globals | 17.13.0 | MIT |
| prettier | 3.9.10 | MIT |
| jsdoc | 4.0.5 | Apache-2.0 |

The page itself has no runtime dependency; the development packages are
pinned with their transitive dependencies in `package-lock.json`.
