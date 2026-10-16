# ADR-0007: Service document templates and per-type file header templates

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-16 |
| Deciders | Platform Enablement Guild (PEG) |
| Step | P0.7 |

## Context

`CLAUDE.md` 6.5.2 requires the same header at the top of every source,
configuration, migration, Dockerfile and Compose file, written in the comment
syntax of the file. The repository will contain more than forty file types
(28 languages plus SQL, YAML, Dockerfiles, Makefiles, HTML, CSS, Typst,
Protobuf and fixed-format COBOL, whose lines end at column 72). `CLAUDE.md`
6.5.5 requires ten documents per service, created from templates by
`scripts/new-service.sh`.

Writing one header template per type by hand would let the wording drift
between types; it also gives the documentation check (P0.9) no
machine-readable way to know how a header looks in each type.

## Decision

- **Headers**: `templates/headers/header.txt` is the single canonical text.
  `templates/headers/styles.psv` describes, per type, the file names it
  applies to, the comment syntax (line prefix or block open/prefix/close),
  the line width (72 for COBOL, 80 otherwise) and an optional preamble that
  must precede the header (shebang, `#lang racket/base`, `<?php`, Ruby magic
  comment; non-shebang preambles are followed by a blank line).
- `templates/headers/<type>.tmpl` are **generated** from those two files by
  `scripts/file-header.sh generate` and committed, so that a reader can see
  the header of every type directly. `scripts/file-header.sh check`, run by
  the `file-header-templates` pre-commit hook, rejects stale templates.
- `scripts/file-header.sh render <type|path> <component> <module> --purpose`
  produces a filled-in header: the type is detected from the path when not
  given, the owning team is looked up in the service catalog or the fixed
  list of areas, and long values are wrapped to the type's width. `detect`
  maps a path to its type and will be reused by P0.9.
- The service catalog moved from `scripts/new-service.sh` to
  `templates/service/catalog.psv`, shared by both scripts.
- JSON has no comment syntax and is exempt from the header; provenance goes
  into `$comment`/`description` where the format allows it.
- **Documents**: `templates/docs/*.md.tmpl` hold the ten documents of
  `CLAUDE.md` 6.5.5 with the corporate metadata table, the statements that
  hold for every service (healthcheck behaviour, network segmentation,
  memory limit and its justification, database, owning team) and
  `TODO(scaffold)` markers for everything only the service author knows.
  `new-service.sh` always renders them; it fails if they are missing.
- `make lint-scaffold` now searches with `git grep` and root-relative
  exclusions. The former `grep --exclude-dir=docs --exclude=Makefile`
  excluded every `docs/` directory and every `Makefile` at any depth, so the
  markers in `services/*/docs/` and `services/*/Makefile` were never
  reported.

## Consequences

- Changing the header wording is one edit in `header.txt` plus
  `scripts/file-header.sh generate`; all types stay identical in content.
- A new file type is one row in `styles.psv`.
- A freshly scaffolded service fails `make lint` until its documents are
  written, which enforces `CLAUDE.md` 8.12 ("document during, not after").
- Two defects of P0.4 fixed in this step: `render` in `new-service.sh` did
  not escape `&` (the team "Trust & Identity Board" came out as
  "Trust __TEAM__ Identity Board"), and the Compose `build.context` was
  relative to the repository root although included files resolve paths
  relative to `compose/`.
