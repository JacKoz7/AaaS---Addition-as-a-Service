# ADR-0006: GitHub Actions continuous integration

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-16 |
| Deciders | Platform Enablement Guild (PEG) |
| Step | P0.6 |

## Context

`CLAUDE.md` 6.3, 7.1 and 9.1 require that `main` is always green, that every
commit follows Conventional Commits with a `Step:` trailer, and that every
component is built, linted and unit-tested. The repository will hold 35
services and 17 microfrontends in 28+ languages; building all of them on every
push would take far longer than the change itself warrants. Every component
already builds, lints and tests inside Docker through its own Makefile
(ADR-0002), so CI needs no language toolchains on the runner.

## Decision

- One workflow, `.github/workflows/ci.yml`, triggered on pushes to `main` and
  `step/**`, on pull requests, and manually (`workflow_dispatch`, with an
  option to select every component).
- **Jobs**:
  - `lint (repository)`: `make lint-repo lint-scaffold temporary`, i.e. the
    same pre-commit hooks developers run locally, plus the scaffold-marker
    check and the `TEMPORARY` marker listing. `no-commit-to-branch` is
    skipped through `SKIP`, because CI legitimately checks out `main`.
  - `commitlint`: lints every commit of the pull request (`base..head`) or of
    the pushed range (`before..after`). For a newly pushed branch or a manual
    run it lints the commits not yet on `origin/main`, or the last commit when
    the run is on `main` itself.
  - `detect changed components`: `scripts/ci/changed-components.sh` prints the
    matrix as JSON. A component is a `services/<name>` or `frontend/<name>`
    directory with a Makefile. A change inside it selects it; a change to a
    global path (`Makefile`, `docker-compose.yml`, `templates/service/`,
    `contracts/`, `.github/workflows/ci.yml`, `scripts/ci/`) selects every
    component. A run without a usable base (first push of `main`) also
    selects every component.
  - `<path>` (matrix, one job per component, `fail-fast: false`):
    `make build-<compose service>`, `make lint-<name>`, `make test-<name>`.
    The Compose service is `<name>` for services and `frontend-<name>` for
    microfrontends.
  - `ci-ok`: a single aggregate status for branch protection; it fails if any
    job failed or was cancelled, and treats skipped jobs (empty matrix) as
    success.
- **Supply chain**: third-party actions are pinned to full commit SHAs with
  the release tag in a comment (`actions/checkout` v7.0.1,
  `actions/setup-python` v7.0.0, `actions/setup-node` v7.1.0, `actions/cache`
  v6.1.0). `permissions: contents: read` at workflow level. Tool versions
  (pre-commit 4.7.0, commitlint 21.2.3, Node 24, Python 3.13) are set in the
  workflow `env` block.
- **actionlint** is added to the pre-commit hooks as a `docker_image` hook
  (`rhysd/actionlint:1.7.12`, Docker Hub), so the workflow is linted locally
  and in CI with the same pinned version, without a host install.
- **Runner**: `ubuntu-24.04` (pinned, not `ubuntu-latest`), which ships Docker
  and Docker Compose v2 required by the Makefiles.
- `concurrency` cancels superseded runs of the same branch or pull request.

## Consequences

- A push touching only `services/digit-7/` builds and tests only `digit-7`.
  A contract change rebuilds every component, which is slow but safe: the
  contracts generate code inside the components.
- Until the first component exists (Phase 1), the matrix is empty and only
  the lint and commitlint jobs do real work.
- Image layer caching between runs is not configured yet; if build times
  become a problem, a BuildKit cache (`type=gha`) is the next step and will be
  recorded in a new ADR.
- Commits made on GitHub (for example a squash merge with a generated message)
  must still carry a `Step:` trailer or commitlint fails on `main`; the local
  merge protocol of `CLAUDE.md` 8.1 avoids this.
