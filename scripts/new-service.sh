#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/new-service.sh
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Scaffolds a new service from templates/service/: directory
#                  layout, Dockerfile, Makefile, README, .dockerignore, Compose
#                  blocks in compose/services.yml and the database password
#                  placeholder in .env.example.
# Related Docs:    CLAUDE.md (sections 2, 6.1, 6.2), ADR-0002, ADR-0004,
#                  templates/service/
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
# Catalog: name|language|team|abbr|database|kind|purpose
# kind: container (database runs as <name>-db) or embedded (in-process).
# ---------------------------------------------------------------------------
CATALOG='
gateway|traefik|Platform Enablement Guild|PEG|Redis|container|Single entry point, routing and forwardAuth middleware.
auth|keycloak|Trust & Identity Board|TIB|PostgreSQL|container|OAuth2/OIDC provider with one-click guest login.
rate-limiter|ruby|Trust & Identity Board|TIB|Redis|container|forwardAuth endpoint: JWT verification and per-user addition limits.
idempotency|typescript|Trust & Identity Board|TIB|Valkey|container|Maps an Idempotency-Key of "=" to exactly one task.
feature-flags|unleash|Trust & Identity Board|TIB|PostgreSQL|container|Feature flag server holding addition_enabled.
service-discovery|consul|Platform Enablement Guild|PEG|Raft|embedded|Service registry with health checks.
config-server|php|Platform Enablement Guild|PEG|MongoDB|container|Configuration fetched by every service at startup.
secrets|openbao|Platform Enablement Guild|PEG|Raft|embedded|Database credentials and AppRole per service.
schema-registry|apicurio|Platform Enablement Guild|PEG|PostgreSQL|container|JSON Schema registry for every event.
parser|ocaml|Arithmetic Excellence Center|AEC|SQLite|embedded|Turns the text expression into an AST.
validator|rust|Arithmetic Excellence Center|AEC|MariaDB|container|Checks that both operands are within 0-99999.
operator-registry|crystal|Arithmetic Excellence Center|AEC|PostgreSQL|container|Resolves "+" to the addition saga and checks the feature flag.
digit-0|c|Arithmetic Excellence Center|AEC|SQLite|embedded|Authoritative source for the value and successor of digit 0.
digit-1|cpp|Arithmetic Excellence Center|AEC|SQLite|embedded|Authoritative source for the value and successor of digit 1.
digit-2|fortran|Arithmetic Excellence Center|AEC|SQLite|embedded|Authoritative source for the value and successor of digit 2.
digit-3|pascal|Arithmetic Excellence Center|AEC|SQLite|embedded|Authoritative source for the value and successor of digit 3.
digit-4|lua|Arithmetic Excellence Center|AEC|SQLite|embedded|Authoritative source for the value and successor of digit 4.
digit-5|dart|Arithmetic Excellence Center|AEC|SQLite|embedded|Authoritative source for the value and successor of digit 5.
digit-6|swift|Arithmetic Excellence Center|AEC|SQLite|embedded|Authoritative source for the value and successor of digit 6.
digit-7|gleam|Arithmetic Excellence Center|AEC|SQLite|embedded|Authoritative source for the value and successor of digit 7.
digit-8|d|Arithmetic Excellence Center|AEC|SQLite|embedded|Authoritative source for the value and successor of digit 8.
digit-9|racket|Arithmetic Excellence Center|AEC|SQLite|embedded|Authoritative source for the value and successor of digit 9 (next is 0 with carry).
successor|haskell|Arithmetic Excellence Center|AEC|CouchDB|container|Computes n+1 through the digit services and carry.
carry|elixir|Arithmetic Excellence Center|AEC|Mnesia|embedded|Propagates a carry to higher digit positions.
saga-orchestrator|go|Transaction Integrity Office|TIO|PostgreSQL|container|Temporal workflow of one addition, compensation and task status.
consensus|go|Transaction Integrity Office|TIO|BoltDB|embedded|Three replicas compute independently; Raft commits the majority.
distributed-lock|etcd|Transaction Integrity Office|TIO|Raft|embedded|Locks ordering ledger appends and invoice numbering.
outbox-relay|debezium|Transaction Integrity Office|TIO|PostgreSQL|container|Publishes the saga outbox to Redpanda via CDC.
dead-letter|perl|Transaction Integrity Office|TIO|MongoDB|container|Retries failed events and signals compensation.
ledger|nim|Transaction Integrity Office|TIO|immudb|container|Immutable hash-chained record of every result.
expression-assembler|csharp|Customer Experience Tribe|CXT|SurrealDB|container|Turns key presses into an expression and starts a task.
commutator|zig|Arithmetic Excellence Center|AEC|LMDB|embedded|Swaps operands so that b is the smaller one.
cloud-notary|python|Cloud Governance Committee|CGC|DynamoDB|container|AWS Lambda verifying the hash chain and storing a copy.
stopwatch|kotlin|Customer Experience Tribe|CXT|TimescaleDB|container|Measures the official waiting time and streams it over SSE.
billing|lisp|Revenue Operations Unit|ROU|Firebird|container|Issues the 0.00 PLN invoice as PDF.
'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  sed -n '/^# Usage:/,/^# marker remains/p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

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

# render <template> : substitutes every __PLACEHOLDER__ and prints to stdout.
render() {
  sed -e "s|__SERVICE_UPPER__|${SERVICE_UPPER}|g" \
      -e "s|__SERVICE__|${SERVICE}|g" \
      -e "s|__LANGUAGE__|${LANGUAGE}|g" \
      -e "s|__TEAM_ABBR__|${TEAM_ABBR}|g" \
      -e "s|__TEAM__|${TEAM}|g" \
      -e "s|__DB_KIND__|${DB_KIND}|g" \
      -e "s|__DB_IMAGE__|${DB_IMAGE}|g" \
      -e "s|__DB__|${DB}|g" \
      -e "s|__PURPOSE__|${PURPOSE}|g" \
      -e "s|__MEM_REASON__|${MEM_REASON}|g" \
      -e "s|__MEM__|${MEM}|g" \
      -e "s|__TOOLCHAIN_IMAGE__|${TOOLCHAIN_IMAGE}|g" \
      -e "s|__RUNTIME_IMAGE__|${RUNTIME_IMAGE}|g" \
      -e "s|__FMT_COMMAND__|${FMT_COMMAND}|g" \
      "$1"
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
[ -e "$SERVICE_DIR" ] && die "$SERVICE_DIR already exists"
grep -qE "^  ${SERVICE}:" "$COMPOSE_FILE" && die "$COMPOSE_FILE already defines '${SERVICE}'"

# Catalog lookup.
ENTRY="$(printf '%s\n' "$CATALOG" | grep -E "^${SERVICE}\|" || true)"
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

SERVICE_UPPER="$(printf '%s' "$SERVICE" | tr 'a-z-' 'A-Z_')"
memory_limit "$LANGUAGE"
DB_IMAGE="TODO-scaffold/$(printf '%s' "$DB" | tr 'A-Z' 'a-z'):pin-me"
TOOLCHAIN_IMAGE="TODO-scaffold/${LANGUAGE}-toolchain:pin-me"
RUNTIME_IMAGE="TODO-scaffold/${LANGUAGE}-runtime:pin-me"
FMT_COMMAND="echo 'TODO(scaffold): formatter command for ${LANGUAGE}' \&\& exit 1"

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

# Corporate documents (templates/docs/ arrives in step P0.7).
if [ -d templates/docs ] && [ -n "$(ls -A templates/docs 2>/dev/null)" ]; then
  for t in templates/docs/*.md.tmpl; do
    render "$t" > "$SERVICE_DIR/docs/$(basename "${t%.tmpl}")"
  done
  echo "    docs/ populated from templates/docs/"
else
  printf '# TODO(scaffold): service documents (templates/docs/ arrives in step P0.7).\n' > "$SERVICE_DIR/docs/.gitkeep"
  echo "    docs/ left empty: templates/docs/ not available yet (step P0.7)"
fi

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
  1. Replace every TODO(scaffold) above (make lint fails while any remains).
  2. Implement GET /health and GET /metrics on port 8080 (CLAUDE.md 6.1).
  3. make build-${SERVICE} && make test-${SERVICE} && make lint-${SERVICE}
  4. make up and confirm ${SERVICE} is healthy; record RAM in docs/CAPACITY.md.
MSG
