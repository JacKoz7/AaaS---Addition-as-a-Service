# ADR-0010: Documentation portal and changelogs

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-16 |
| Deciders | Platform Enablement Guild (PEG) |
| Step | P0.10 |

## Context

`CLAUDE.md` 6.5.7 requires `make docs` to generate the API documentation of
every service with its native tool and to assemble everything into one
MkDocs Material portal in `docs/site/`, served by `make docs-serve` on port
8000, with a home page showing the service map, a service catalog, an event
catalog generated from JSON Schema, an API catalog (OpenAPI and proto), ADRs,
RFCs, the risk register and changelogs. `CLAUDE.md` 6.5.8 requires
per-service changelogs generated from commits by git-cliff (commit scope =
service) and completed by hand with a "Business Impact" section.

Three constraints shape the solution:

- MkDocs reads one `docs_dir`, but the documents live in the repository root,
  `docs/`, `services/*/docs/`, `frontend/*/docs/` and `contracts/`.
  `docs/` cannot be the `docs_dir` because MkDocs rejects a `site_dir`
  (`docs/site`) inside it.
- Documents link to repository paths (`../../README.md`, `docs/adr/`,
  `CLAUDE.md`, scripts) so that they work on GitHub. In the portal, a link to
  a file that is not a page is a broken link, and the build must have no
  warnings.
- No tool may be required on the host besides Docker and `make` (ADR-0002).

## Decision

- **Tool image** `infra/docs-portal/Dockerfile`: `squidfunk/mkdocs-material`
  9.7.7 (MkDocs 1.6.1, multi-arch) plus interrogate 1.7.0, built locally as
  `aaas/docs-portal:dev` by `make docs-image`. It is a developer tool, not a
  Compose service. The repository is mounted at `/docs` and the container
  runs with the caller's UID.
- **Portal assembler** `scripts/docs-portal.py`, loaded by MkDocs as a hook
  (`hooks:` in `mkdocs.yml`) and run before every build, including every
  rebuild of `mkdocs serve`. It writes `build/portal/` (git-ignored), the
  `docs_dir`:
  - mirrors the root documents (`README.md`, `CONTRIBUTING.md`,
    `CODE_OF_CONDUCT.md`, `SECURITY.md`), `docs/` without `docs/site`,
    component READMEs and `docs/` trees and Markdown under `contracts/`,
    under their repository paths; `LICENSE` and `CODEOWNERS` are copied as
    plain files;
  - turns the root `README.md` into the home page `index.md` and appends the
    service map (Mermaid, services grouped by owning team, solid when the
    service directory exists, dashed when planned) and the portal contents;
  - rewrites relative links: to the portal page when the target is in the
    portal, to the `index.md`/`README.md` of a linked directory, and to the
    file on GitHub (`blob/main`, `tree/main`) when the target exists only in
    the repository; a target that exists nowhere is left as it is, so the
    strict build reports it. Code blocks and code spans are not touched;
  - generates `catalog/services.md` (from `templates/service/catalog.psv`,
    the catalog already shared by the scaffolding and header scripts),
    `catalog/events.md` (from `contracts/events/**/*.json`),
    `catalog/api.md` (from `contracts/http/*.yaml`, `contracts/proto/**`
    and the native API documentation), `catalog/changelogs.md`, and the
    indexes `docs/adr/index.md`, `docs/rfc/index.md` and
    `docs/progress/steps/index.md` (title and metadata of every record);
  - writes a file only when its content changes and deletes stale files, so
    the development server, which watches `build/portal`, does not rebuild
    in a loop; it refuses any output directory other than `build/portal`,
    because it deletes unregistered files.
  - Python was chosen over shell because the generator parses JSON Schema
    now and OpenAPI later, and because MkDocs hooks are Python. It is checked
    by interrogate (100%) and its doctests by `make doc-coverage-repo`, and
    linted and formatted by ruff (pre-commit, `ruff.toml`).
- **`mkdocs.yml`**: `docs_dir: build/portal`, `site_dir: docs/site`, Material
  theme with light and dark palettes, Mermaid through `pymdownx.superfences`,
  link and anchor validation raised to warnings, a static navigation of the
  catalogs, indexes, governance and engineering documents (other pages are
  reached from the catalogs). `pre-commit`'s `check-yaml` skips the file
  because of the `!!python/name` tag the Mermaid fence needs; yamllint
  still checks it.
- **Make targets**: `docs` = `api-docs` + `docs-portal`; `docs-portal` runs
  `mkdocs build --strict`; `docs-serve` runs `mkdocs serve` on
  `127.0.0.1:${DOCS_PORT:-8000}`; `api-docs` and `api-docs-<component>`
  export native API documentation; `doc-coverage-repo` is part of
  `doc-coverage`; `clean` also removes `build/portal` and `build/api-docs`.
- **Native API documentation**: the service contract (ADR-0004) gains an
  `api-docs-build` stage that writes HTML with an `index.html` to
  `/api-docs`, and a `scratch` stage `api-docs` that holds only that tree.
  The component target `make api-docs` exports it with
  `docker build --target api-docs --output type=local,dest=...` to
  `build/api-docs/<component>/`; the assembler publishes it under
  `api/<component>/` and links it from the service and API catalogs.
  `scripts/new-service.sh` writes the generator of the language (the table
  in `CLAUDE.md` 6.5.3) into the stage's `TODO(scaffold)` marker; platform
  products without own code (Traefik, Keycloak, ...) render an `index.html`
  describing their configuration.
- **`API.md`** of a service is generated from the contracts by the steps
  that introduce each contract type (events in P1.3, proto in P2.1, OpenAPI
  in P2.2), reusing the readers of the assembler; until then it is kept in
  sync with the contracts by hand.
- **Changelogs**: `cliff.toml` renders one release section: commits whose
  scope equals `AAAS_SCOPE`, grouped feat → Added, perf/refactor/contract/
  build/infra → Changed, fix → Fixed (docs, test, ci, chore and style are
  left out; breaking changes are marked **BREAKING**), followed by an empty
  "Business Impact" heading. `scripts/changelog.sh <component> [X.Y.Z]`
  (`make changelog-<component> [VERSION=X.Y.Z]`) runs the pinned
  `orhunp/git-cliff:2.14.2` image with the tag pattern `^<scope>/v`: without
  a version it prints the unreleased changes; with one it inserts the
  section under `## [Unreleased]` of the component's `CHANGELOG.md` (it
  refuses an existing version or tag). The scope and tag prefix are the
  service name, or `frontend-<name>` for a microfrontend (`CLAUDE.md` 7.1).
- **CI**: a `docs` job runs `make docs-portal` and `make doc-coverage-repo`;
  the component matrix runs `make api-docs-<component>`.
- **C4**: the system context diagram is Mermaid `C4Context` in
  `docs/architecture/c4/context.md` (renders on GitHub and in the portal);
  container and component diagrams follow in P11.4.

## Consequences

- One command builds a portal that contains every document and cannot drift
  from the catalog, the contracts or the ADRs, because the catalogs are
  generated from them. A broken link fails the build locally and in CI.
- The portal is a derived artifact: `build/portal` and `docs/site` are never
  committed, and documents are edited only in the repository.
- `make docs` fails while any component still has its scaffold
  `api-docs-build` stage, consistent with `make lint-scaffold`.
- Material for MkDocs prints a warning that MkDocs 2.0 will be incompatible;
  the image pins MkDocs 1.6.1 and silences the banner
  (`NO_MKDOCS_2_WARNING`). The risk is recorded as R-009 in the risk
  register; the assembler produces plain Markdown, so it is reusable with
  another generator.
- The Mermaid library is loaded by the browser from a CDN; without internet
  access the diagrams show as code blocks while the rest of the portal works.
- Amends ADR-0004 (new `api-docs` stage and target in the service contract).
