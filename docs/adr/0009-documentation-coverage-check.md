# ADR-0009: Documentation coverage check

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-16 |
| Deciders | Platform Enablement Guild (PEG) |
| Step | P0.9 |

## Context

`CLAUDE.md` 6.5.4 requires `make doc-coverage` to report 100% for every
service. Ten languages have a native tool (rustdoc/clippy, interrogate,
revive, CS1591, detekt, eslint-plugin-jsdoc, yard, phpcs, doctor, haddock);
the remaining ones (C, C++, Fortran, Free Pascal, Lua, Dart, Swift, Gleam, D,
Racket, Nim, Crystal, Zig, Perl, Common Lisp, COBOL, OCaml, shell, SQL, YAML
and the rest) are covered by `scripts/doc-check.sh`: a file header and a
comment before every top-level definition. The header (`CLAUDE.md` 6.5.2) is
mandatory for every language, including those with a native tool.

## Decision

- **`scripts/doc-check.sh`** checks every tracked or untracked, not ignored
  file (or the files given as arguments):
  - the header in the exact comment syntax of the file's type from
    `templates/headers/styles.psv` (preamble, block opener, prefix), the
    SPDX and copyright lines, the six fields in order and non-empty, the
    team among the eight of `CLAUDE.md` 6.5.1 and the classification among
    PUBLIC, INTERNAL and CONFIDENTIAL;
  - for types listed in `scripts/lib/doc-definitions.psv`, a comment line
    directly above every top-level definition (lines matching a `skip`
    pattern such as `.PHONY:` may sit in between; an inline pattern such as
    `## help` on a make target also counts).
  - A file whose name matches no header type is an error, so a new file type
    cannot slip past the check unnoticed: it needs a row in `styles.psv` or
    an entry in `.doc-check-ignore`.
- It prints a table per component (`services/<name>`, `frontend/<name>`,
  `repo`): headers, definitions and coverage
  `(valid headers + documented definitions) / (files + definitions)`, and
  exits 1 below 100%.
- **Exemptions** live in `.doc-check-ignore`, each with its reason: Markdown
  (documents follow the templates of 6.5.5/6.5.6 instead), JSON (no
  comments), `LICENSE`, templates with placeholders.
- **Definition patterns are added with the languages**: P0.9 ships rows for
  shell and make, the two languages present now. The step that adds the
  first file of another language without a native tool adds its row; the
  scaffold's `doc-coverage` stage says so.
- **Shared code**: the style functions moved from `scripts/file-header.sh`
  to `scripts/lib/header-styles.sh`, sourced by both scripts.
- **Make targets**: `make doc-check` (the script), `make doc-coverage`
  (`doc-check` plus `make doc-coverage-<component>` for every component),
  `make doc-coverage-<component>` (delegated to the component Makefile).
- **Stage contract** (amends ADR-0004): the service Dockerfile gains a
  `doc-coverage` stage running the native tool of the language;
  `new-service.sh` writes the tool required by `CLAUDE.md` 6.5.4 into the
  stage's `TODO(scaffold)` marker.
- **Enforcement**: a `doc-check` pre-commit hook checks staged files; CI runs
  `make doc-check` in the lint job and `make doc-coverage-<component>` in
  the component matrix.

## Consequences

- The repository is held at 100% from this step on; writing the first
  undocumented shell function fails the commit.
- The definition check is a heuristic based on line patterns: it proves that
  a comment exists, not that it contains every field of `CLAUDE.md` 6.5.3.
  Field completeness is the responsibility of review and, where available,
  of the native tools.
- The check is plain bash and awk (bash 3.2 compatible), so it runs on the
  host and in CI without a container; on the current repository it takes
  about one second.
