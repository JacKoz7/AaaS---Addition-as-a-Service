#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/new-service.sh
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Scaffolds a new service from templates/service/: directory
#                  layout, Dockerfile, Makefile, README, .dockerignore, the
#                  corporate documents from templates/docs/, Compose blocks in
#                  compose/services.yml and the database password placeholder
#                  in .env.example.
# Related Docs:    CLAUDE.md (sections 2, 6.1, 6.2, 6.5), ADR-0002, ADR-0004,
#                  ADR-0007, ADR-0010, templates/service/, templates/docs/
#
# Usage:
#   scripts/new-service.sh <name> <language> [--team "<Team Name> (ABBR)"]
#                          [--db <database>] [--embedded] [--purpose "<text>"]
#
# <name> must be kebab-case. Services listed in the catalog below (CLAUDE.md
# section 2) get their team, database and purpose filled in automatically;
# the <language> argument is checked against the catalog. Unknown names need
# --team and --db.
#
# Every generated file contains `TODO(scaffold)` markers where language- or
# database-specific content must be written. `make lint` fails while any
# marker remains, so a scaffold cannot be merged unfinished.

set -euo pipefail

# ---------------------------------------------------------------------------
# Catalog: templates/service/catalog.psv (name|language|team|abbr|database|
# kind|purpose), shared with scripts/file-header.sh.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# usage: print the usage block of this file and exit with status 2.
usage() {
  sed -n '/^# Usage:/,/^# marker remains/p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

# die <message>: print an error to stderr and exit with status 1.
die() { echo "error: $*" >&2; exit 1; }

# memory_limit <language>: default mem_limit per language class (CLAUDE.md 6.2)
# and the justification comment placed in the Compose block.
memory_limit() {
  case "$1" in
    c|cpp|fortran|pascal|rust|go|haskell|ocaml|nim|crystal|zig|d|swift|dart|traefik|consul|openbao|etcd)
      MEM="64m"; MEM_REASON="Compiled language: default limit for compiled services (CLAUDE.md 6.2)." ;;
    python|ruby|php|perl|lua|racket|typescript|javascript|lisp|elixir|gleam)
      MEM="128m"; MEM_REASON="Interpreted or VM language: default limit for interpreted services (CLAUDE.md 6.2)." ;;
    java|kotlin|keycloak|apicurio|debezium|unleash)
      MEM="512m"; MEM_REASON="JVM or Node-based platform component: default JVM limit (CLAUDE.md 6.2)." ;;
    *)
      MEM="128m"; MEM_REASON="TODO(scaffold): justify the memory limit for language '$1'." ;;
  esac
}

# doc_tool <language>: set DOC_TOOL to the documentation coverage command
# required for <language> by CLAUDE.md 6.5.4, used as a hint in the
# Dockerfile `doc-coverage` stage of the scaffold.
doc_tool() {
  case "$1" in
    rust) DOC_TOOL="cargo clippy -- -D missing_docs -D clippy::missing_docs_in_private_items (#![deny(missing_docs)] in the crate root)" ;;
    python) DOC_TOOL="interrogate --fail-under 100 --verbose src tests" ;;
    go) DOC_TOOL="revive with the 'exported' rule, plus a check of unexported identifiers" ;;
    csharp) DOC_TOOL="dotnet build with CS1591 treated as an error (TreatWarningsAsErrors / WarningsAsErrors=CS1591)" ;;
    kotlin) DOC_TOOL="detekt with the UndocumentedPublicClass/Function/Property rules active" ;;
    typescript | javascript) DOC_TOOL="eslint with eslint-plugin-jsdoc (jsdoc/require-jsdoc on every declaration)" ;;
    ruby) DOC_TOOL="yard stats --list-undoc, failing unless 100% documented" ;;
    php) DOC_TOOL="phpcs with a ruleset requiring file, class, function and property doc comments" ;;
    elixir) DOC_TOOL="mix doctor (100% moduledoc and doc coverage)" ;;
    haskell) DOC_TOOL="haddock coverage report at 100% for every module" ;;
    *) DOC_TOOL="no native tool for ${1}; scripts/doc-check.sh covers it: add a row to scripts/lib/doc-definitions.psv and keep this stage as a native doc build (or a no-op), see ADR-0009" ;;
  esac
}

# api_doc_tool <language>: set API_DOC_TOOL to the native API documentation
# generator of <language> (CLAUDE.md 6.5.3), used as a hint in the Dockerfile
# `api-docs-build` stage of the scaffold (ADR-0010).
api_doc_tool() {
  local out="write the HTML with an index.html at the root into /api-docs"
  case "$1" in
    go) API_DOC_TOOL="go doc / pkgsite (static export of the package docs): ${out}" ;;
    rust) API_DOC_TOOL="cargo doc --no-deps --document-private-items, copy target/doc: ${out}" ;;
    haskell) API_DOC_TOOL="cabal haddock --haddock-all: ${out}" ;;
    ocaml) API_DOC_TOOL="dune build @doc (odoc), copy _build/default/_doc/_html: ${out}" ;;
    elixir) API_DOC_TOOL="mix docs (ExDoc), copy doc/: ${out}" ;;
    gleam) API_DOC_TOOL="gleam docs build, copy build/dev/docs/<package>: ${out}" ;;
    csharp) API_DOC_TOOL="docfx (XML doc comments): ${out}" ;;
    kotlin) API_DOC_TOOL="Dokka (dokkaHtml): ${out}" ;;
    ruby) API_DOC_TOOL="yard doc --private, copy doc/: ${out}" ;;
    php) API_DOC_TOOL="phpDocumentor (phpdoc -d src -t /api-docs): ${out}" ;;
    python) API_DOC_TOOL="pdoc --docformat google -o /api-docs <package>: ${out}" ;;
    typescript | javascript) API_DOC_TOOL="TypeDoc (TSDoc/JSDoc): ${out}" ;;
    nim) API_DOC_TOOL="nim doc --project --index:on: ${out}" ;;
    crystal) API_DOC_TOOL="crystal docs, copy docs/: ${out}" ;;
    zig) API_DOC_TOOL="zig build-lib -femit-docs: ${out}" ;;
    d) API_DOC_TOOL="ddoc (dmd -D) or adrdox: ${out}" ;;
    dart) API_DOC_TOOL="dart doc, copy doc/api: ${out}" ;;
    swift) API_DOC_TOOL="DocC (swift package generate-documentation --transform-for-static-hosting): ${out}" ;;
    c | cpp) API_DOC_TOOL="Doxygen (HTML output): ${out}" ;;
    fortran) API_DOC_TOOL="FORD: ${out}" ;;
    pascal) API_DOC_TOOL="PasDoc (--format html): ${out}" ;;
    lua) API_DOC_TOOL="LDoc: ${out}" ;;
    racket) API_DOC_TOOL="scribble --html: ${out}" ;;
    perl) API_DOC_TOOL="pod2html for every module: ${out}" ;;
    lisp | cobol) API_DOC_TOOL="the repository export script for ${1} doc comments (CLAUDE.md 6.5.3): ${out}" ;;
    *) API_DOC_TOOL="no source code of its own (${1} is a platform product): render an index.html describing its configuration and linking to the upstream reference, ${out}" ;;
  esac
}

# sed_escape <value>: escapes the characters that are special in the
# replacement part of a sed `s|...|...|` command (backslash, `|` and `&`).
sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

# render <template>: substitutes every __PLACEHOLDER__ and prints to stdout.
# Longer placeholders come first so that __SERVICE_UPPER__ is not consumed by
# __SERVICE__, and __TEAM_ABBR__ not by __TEAM__.
render() {
  local -a args=()
  local pair key value
  for pair in \
    "SERVICE_UPPER=${SERVICE_UPPER}" "SERVICE=${SERVICE}" "LANGUAGE=${LANGUAGE}" \
    "TEAM_ABBR=${TEAM_ABBR}" "TEAM=${TEAM}" "DB_KIND=${DB_KIND}" "DB_IMAGE=${DB_IMAGE}" \
    "DB=${DB}" "PURPOSE=${PURPOSE}" "MEM_REASON=${MEM_REASON}" "MEM=${MEM}" \
    "TOOLCHAIN_IMAGE=${TOOLCHAIN_IMAGE}" "RUNTIME_IMAGE=${RUNTIME_IMAGE}" \
    "FMT_COMMAND=${FMT_COMMAND}" "DATE=${DATE}" "VERSION=${VERSION}" "API_DOC_TOOL=${API_DOC_TOOL}" \
    "DOC_TOOL=${DOC_TOOL}"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    args+=(-e "s|__${key}__|$(sed_escape "$value")|g")
  done
  sed "${args[@]}" "$1"
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

[ $# -ge 2 ] || usage
SERVICE="$1"; LANGUAGE="$2"; shift 2
TEAM=""; TEAM_ABBR=""; DB=""; DB_KIND=""; PURPOSE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --team)     TEAM_ARG="$2"; shift 2 ;;
    --db)       DB="$2"; shift 2 ;;
    --embedded) DB_KIND="embedded"; shift ;;
    --purpose)  PURPOSE="$2"; shift 2 ;;
    -h|--help)  usage ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ "$SERVICE" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "service name must be kebab-case: '$SERVICE'"
[[ "$LANGUAGE" =~ ^[a-z0-9]+$ ]] || die "language must be a single lowercase word (e.g. go, cpp, csharp): '$LANGUAGE'"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SERVICE_DIR="services/${SERVICE}"
TEMPLATES="templates/service"
COMPOSE_FILE="compose/services.yml"
ENV_EXAMPLE=".env.example"

[ -d "$TEMPLATES" ] || die "$TEMPLATES not found"
[ -n "$(ls templates/docs/*.md.tmpl 2>/dev/null)" ] || die "templates/docs/*.md.tmpl not found"
[ -e "$SERVICE_DIR" ] && die "$SERVICE_DIR already exists"
grep -qE "^  ${SERVICE}:" "$COMPOSE_FILE" && die "$COMPOSE_FILE already defines '${SERVICE}'"

# Catalog lookup.
ENTRY="$(grep -E "^${SERVICE}\|" "$TEMPLATES/catalog.psv" || true)"
if [ -n "$ENTRY" ]; then
  IFS='|' read -r _ CAT_LANG CAT_TEAM CAT_ABBR CAT_DB CAT_KIND CAT_PURPOSE <<<"$ENTRY"
  if [ "$CAT_LANG" != "$LANGUAGE" ]; then
    echo "warning: catalog lists '${SERVICE}' as '${CAT_LANG}', you passed '${LANGUAGE}'. Continuing with '${LANGUAGE}'; document the deviation in an ADR." >&2
  fi
  TEAM="$CAT_TEAM"; TEAM_ABBR="$CAT_ABBR"
  DB="${DB:-$CAT_DB}"; DB_KIND="${DB_KIND:-$CAT_KIND}"; PURPOSE="${PURPOSE:-$CAT_PURPOSE}"
fi
if [ -n "${TEAM_ARG:-}" ]; then
  [[ "$TEAM_ARG" =~ ^(.+)\ \(([A-Z]+)\)$ ]] || die "--team must look like 'Team Name (ABBR)'"
  TEAM="${BASH_REMATCH[1]}"; TEAM_ABBR="${BASH_REMATCH[2]}"
fi
[ -n "$TEAM" ] || die "'${SERVICE}' is not in the catalog; pass --team \"<Team Name> (ABBR)\""
[ -n "$DB" ] || die "'${SERVICE}' is not in the catalog; pass --db <database> [--embedded]"
DB_KIND="${DB_KIND:-container}"
PURPOSE="${PURPOSE:-TODO(scaffold): one-sentence purpose of ${SERVICE}.}"

SERVICE_UPPER="$(printf '%s' "$SERVICE" | tr '[:lower:]-' '[:upper:]_')"
memory_limit "$LANGUAGE"
DB_IMAGE="TODO-scaffold/$(printf '%s' "$DB" | tr '[:upper:]' '[:lower:]'):pin-me"
TOOLCHAIN_IMAGE="TODO-scaffold/${LANGUAGE}-toolchain:pin-me"
RUNTIME_IMAGE="TODO-scaffold/${LANGUAGE}-runtime:pin-me"
FMT_COMMAND="echo 'TODO(scaffold): formatter command for ${LANGUAGE}' && exit 1"
DATE="$(date +%Y-%m-%d)"
doc_tool "$LANGUAGE"
api_doc_tool "$LANGUAGE"
VERSION="0.1.0"

# ---------------------------------------------------------------------------
# Generate
# ---------------------------------------------------------------------------

echo "==> scaffolding ${SERVICE} (${LANGUAGE}, ${TEAM_ABBR}, ${DB} ${DB_KIND})"
mkdir -p "$SERVICE_DIR"/{src,migrations,tests,docs}
render "$TEMPLATES/Dockerfile.tmpl"    > "$SERVICE_DIR/Dockerfile"
render "$TEMPLATES/Makefile.tmpl"      > "$SERVICE_DIR/Makefile"
render "$TEMPLATES/README.md.tmpl"     > "$SERVICE_DIR/README.md"
render "$TEMPLATES/dockerignore.tmpl"  > "$SERVICE_DIR/.dockerignore"
for d in src migrations tests; do
  printf '# TODO(scaffold): %s of %s go here; remove this file.\n' "$d" "$SERVICE" > "$SERVICE_DIR/$d/.gitkeep"
done

# Corporate documents (CLAUDE.md 6.5.5): one file per template.
for t in templates/docs/*.md.tmpl; do
  render "$t" > "$SERVICE_DIR/docs/$(basename "${t%.tmpl}")"
done
echo "    docs/ populated from templates/docs/ ($(find "$SERVICE_DIR/docs" -name '*.md' | wc -l | tr -d ' ') documents)"

# Compose blocks: service (+ depends_on or embedded volume), database, volume.
{
  render "$TEMPLATES/compose-service.yml.tmpl"
  if [ "$DB_KIND" = "container" ]; then
    render "$TEMPLATES/compose-depends.yml.tmpl"
    render "$TEMPLATES/compose-db.yml.tmpl"
  else
    render "$TEMPLATES/compose-embedded-volume.yml.tmpl"
  fi
} > "$SERVICE_DIR/.compose-block.tmp"
render "$TEMPLATES/compose-volume.yml.tmpl" > "$SERVICE_DIR/.compose-volume.tmp"

python3 - "$COMPOSE_FILE" "$SERVICE_DIR/.compose-block.tmp" "$SERVICE_DIR/.compose-volume.tmp" <<'PY'
import sys, pathlib
compose, block, volume = (pathlib.Path(a) for a in sys.argv[1:4])
s = compose.read_text()
s = s.replace("services: {}\n", "services:\n").replace("volumes: {}\n", "volumes:\n")
marker = "# AAAS:VOLUMES"
if marker not in s:
    sys.exit("error: marker '%s' not found in %s" % (marker, compose))
head, tail = s.split(marker, 1)
s = head + block.read_text() + marker + tail
if not s.endswith("\n"):
    s += "\n"
s += volume.read_text()
compose.write_text(s)
PY
rm -f "$SERVICE_DIR/.compose-block.tmp" "$SERVICE_DIR/.compose-volume.tmp"

# Database password placeholder (moves to OpenBao in P5.3).
if ! grep -q "^${SERVICE_UPPER}_DB_PASSWORD=" "$ENV_EXAMPLE"; then
  printf '%s_DB_PASSWORD=change-me\n' "$SERVICE_UPPER" >> "$ENV_EXAMPLE"
fi

# Validate the Compose model if Docker is available.
if docker compose config --quiet 2>/dev/null; then
  echo "    docker compose config: ok"
else
  echo "    docker compose config: skipped or failed (is Docker running?)" >&2
fi

cat <<MSG

Scaffolded ${SERVICE_DIR}. Remaining TODO(scaffold) markers:
MSG
grep -rn 'TODO(scaffold)' "$SERVICE_DIR" "$COMPOSE_FILE" | sed 's/^/    /'
cat <<MSG

Next:
  1. Replace every TODO(scaffold) above, including those in docs/
     (make lint fails while any remains).
  2. Start every new source file with a header in its language's syntax:
     scripts/file-header.sh render <type|path> ${SERVICE} <module> --purpose "..."
  3. Implement GET /health and GET /metrics on port 8080 (CLAUDE.md 6.1).
  4. make build-${SERVICE} && make test-${SERVICE} && make lint-${SERVICE}
     && make doc-coverage-${SERVICE}
  5. make up and confirm ${SERVICE} is healthy; record RAM in docs/CAPACITY.md.
MSG
