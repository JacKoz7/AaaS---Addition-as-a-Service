# File header templates

Every source, configuration, migration, Dockerfile and Compose file starts with
the header defined in `CLAUDE.md`, section 6.5.2. This directory holds that
header in the comment syntax of every file type used in the repository.

| File | Role |
| --- | --- |
| `header.txt` | Canonical header text with `__PLACEHOLDER__` fields. Edit the wording here only. |
| `styles.psv` | Comment syntax per header type: file name matches, block or line comment, line width, preamble. |
| `<type>.tmpl` | Generated: `header.txt` wrapped in the syntax of `<type>`. Do not edit by hand. |

## Placeholders

| Placeholder | Value |
| --- | --- |
| `__COMPONENT__` | Service name (`successor`), frontend element (`frontend-key-3`) or area (`repo`, `compose`, `contracts`, `observability`, `aws`) |
| `__MODULE__` | Module, package, class or file path, in the language's own notation |
| `__TEAM__`, `__TEAM_ABBR__` | Owning team from `CLAUDE.md` 6.5.1, e.g. `Arithmetic Excellence Center`, `AEC` |
| `__CLASSIFICATION__` | `PUBLIC`, `INTERNAL` (default) or `CONFIDENTIAL` |
| `__PURPOSE__` | What the file is for, in one or more sentences |
| `__RELATED_DOCS__` | Documents, ADRs and contracts that explain the file |

## Rendering a header

Use the renderer instead of filling a template by hand; it looks up the
owning team, wraps long values to the line width of the type (72 columns for
fixed-format COBOL, 80 otherwise) and adds the preamble the type needs
(shebang, `#lang`, `<?php`, Ruby magic comment):

```sh
scripts/file-header.sh render go successor Successor.Core \
  --purpose "Computes the successor of a natural number by orchestrating digit services and the carry service." \
  --docs "services/successor/docs/SERVICE_CHARTER.md, ADR-0007"

scripts/file-header.sh render services/ledger/src/chain.nim ledger chain \
  --purpose "Computes the hash chain of ledger entries."   # type detected from the path

scripts/file-header.sh detect services/digit-2/src/digit.f90   # -> fortran
scripts/file-header.sh list                                    # every type and its matches
```

## Changing the header or adding a file type

1. Edit `header.txt` (wording) or add a row to `styles.psv` (new file type).
2. Run `scripts/file-header.sh generate`.
3. Commit the regenerated `*.tmpl` files together with the change. The
   `file-header-templates` pre-commit hook runs `scripts/file-header.sh check`
   and rejects the commit when the templates are stale.

## Files without a header

JSON has no comment syntax. JSON files (event schemas, `package.json`,
example payloads) carry their provenance in fields the format allows, such as
`$comment` and `description` in JSON Schema; the documentation check (P0.9)
exempts `*.json`. Generated files (lock files, generated code) are also exempt
and are listed in that check.
