#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/file-header.sh
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Renders the mandatory file header (CLAUDE.md 6.5.2) in the
#                  comment syntax of any file type used in the repository,
#                  regenerates the per-type templates in templates/headers/
#                  and checks that they are in sync with the canonical text.
# Related Docs:    templates/headers/README.md, templates/headers/styles.psv,
#                  ADR-0007
#
# Usage:
#   scripts/file-header.sh render <type> <component> <module> --purpose "<text>"
#                          [--docs "<text>"] [--team "<Team Name> (ABBR)"]
#                          [--classification PUBLIC|INTERNAL|CONFIDENTIAL]
#   scripts/file-header.sh detect <path>     print the header type of a file
#   scripts/file-header.sh list              print every type and its matches
#   scripts/file-header.sh generate          rewrite templates/headers/*.tmpl
#   scripts/file-header.sh check             fail if the templates are stale
#
# <type> is a row of templates/headers/styles.psv (e.g. go, cobol, sql) or a
# path, in which case the type is detected from its name. The owning team is
# taken from --team, the service catalog (templates/service/catalog.psv),
# `frontend-*` components (CXT) or the repository areas listed in team_for.
# Example:
#   scripts/file-header.sh render go successor Successor.Core \
#     --purpose "Computes the successor of a natural number." --docs "ADR-0007"

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HEADERS_DIR="${ROOT}/templates/headers"
STYLES="${HEADERS_DIR}/styles.psv"
CANONICAL="${HEADERS_DIR}/header.txt"
CATALOG="${ROOT}/templates/service/catalog.psv"

# Width of the label column ("Purpose:         ") in the canonical header.
LABEL_WIDTH=17

# usage: print the usage block of this file and exit with status 2.
usage() {
  sed -n '/^# Usage:/,/^# Example:/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
  exit 2
}

# die <message>: print an error to stderr and exit with status 1.
die() {
  echo "error: $*" >&2
  exit 1
}

# style_rows: print the data rows of styles.psv (no comments, no blank lines).
style_rows() {
  grep -vE '^(#|$)' "$STYLES"
}

# load_style <type>: set S_OPEN, S_PREFIX, S_CLOSE, S_WIDTH and S_PREAMBLE
# from the styles.psv row of <type> (the type and matches columns are skipped).
load_style() {
  local row
  row="$(style_rows | grep -E "^${1}\|" || true)"
  [ -n "$row" ] || die "unknown header type '${1}' (see: scripts/file-header.sh list)"
  IFS='|' read -r _ _ S_OPEN S_PREFIX S_CLOSE S_WIDTH S_PREAMBLE <<<"$row"
}

# detect_type <path>: print the header type whose `matches` column covers the
# base name of <path> (exact name or extension suffix); fail if none does.
detect_type() {
  local base type matches match
  local -a list
  base="$(basename "$1")"
  while IFS='|' read -r type matches _; do
    IFS=',' read -r -a list <<<"$matches"
    for match in "${list[@]+"${list[@]}"}"; do
      case "$match" in
        .*) [[ "$base" == *"$match" ]] && { echo "$type"; return 0; } ;;
        *) [ "$base" = "$match" ] && { echo "$type"; return 0; } ;;
      esac
    done
  done < <(style_rows)
  return 1
}

# resolve_type <type-or-path>: print the type itself if it is a known type,
# otherwise the type detected from the path.
resolve_type() {
  if style_rows | grep -qE "^${1}\|"; then
    echo "$1"
  else
    detect_type "$1" || die "no header type known for '${1}' (see: scripts/file-header.sh list)"
  fi
}

# comment: read plain header lines on stdin and print them wrapped in the
# loaded comment style, preceded by the preamble line if the style has one.
# A preamble other than a shebang is followed by one blank line, as rubocop
# (Layout/EmptyLineAfterMagicComment), PSR-12 and Racket style expect.
comment() {
  local line trimmed_prefix
  trimmed_prefix="${S_PREFIX%"${S_PREFIX##*[! ]}"}"
  if [ -n "$S_PREAMBLE" ]; then
    echo "$S_PREAMBLE"
    [[ "$S_PREAMBLE" == "#!"* ]] || echo
  fi
  [ -z "$S_OPEN" ] || echo "$S_OPEN"
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      echo "$trimmed_prefix"
    else
      echo "${S_PREFIX}${line}"
    fi
  done
  [ -z "$S_CLOSE" ] || echo "$S_CLOSE"
}

# team_for <component>: print "Team Name|ABBR" for <component>, looked up in
# the service catalog, then in the fixed list of frontend and repository
# areas (CLAUDE.md 6.5.1); print nothing if unknown.
team_for() {
  local row team abbr
  row="$(grep -E "^${1}\|" "$CATALOG" || true)"
  if [ -n "$row" ]; then
    IFS='|' read -r _ _ team abbr _ <<<"$row"
    echo "${team}|${abbr}"
    return
  fi
  case "$1" in
    frontend | frontend-*) echo "Customer Experience Tribe|CXT" ;;
    repo | compose | contracts | ci | templates | scripts | docs) echo "Platform Enablement Guild|PEG" ;;
    observability) echo "Observability Steering Group|OSG" ;;
    aws) echo "Cloud Governance Committee|CGC" ;;
    *) ;;
  esac
}

# field <label-line> <value> <width>: print the label and <value>, wrapping
# the value at <width> columns with continuation lines aligned under it.
field() {
  local label="$1" value="$2" width="$3" first=1 chunk
  while IFS= read -r chunk; do
    chunk="${chunk%"${chunk##*[! ]}"}"
    if [ "$first" -eq 1 ]; then
      printf '%s%s\n' "$label" "$chunk"
      first=0
    else
      printf '%*s%s\n' "$LABEL_WIDTH" "" "$chunk"
    fi
  done < <(printf '%s\n' "$value" | fold -s -w "$width")
}

# render <type> <component> <module> [options]: print a filled-in header.
render() {
  [ $# -ge 3 ] || usage
  local type component="$2" module="$3" purpose="" docs="" team_arg="" classification="INTERNAL"
  local team abbr lookup width
  type="$(resolve_type "$1")"
  shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --purpose) purpose="$2"; shift 2 ;;
      --docs) docs="$2"; shift 2 ;;
      --team) team_arg="$2"; shift 2 ;;
      --classification) classification="$2"; shift 2 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [ -n "$purpose" ] || die "--purpose is required"
  case "$classification" in
    PUBLIC | INTERNAL | CONFIDENTIAL) ;;
    *) die "--classification must be PUBLIC, INTERNAL or CONFIDENTIAL" ;;
  esac
  if [ -n "$team_arg" ]; then
    [[ "$team_arg" =~ ^(.+)\ \(([A-Z]+)\)$ ]] || die "--team must look like 'Team Name (ABBR)'"
    team="${BASH_REMATCH[1]}"
    abbr="${BASH_REMATCH[2]}"
  else
    lookup="$(team_for "$component")"
    [ -n "$lookup" ] || die "no owning team known for '${component}'; pass --team \"<Team Name> (ABBR)\""
    team="${lookup%%|*}"
    abbr="${lookup#*|}"
  fi
  if [ -z "$docs" ]; then
    if grep -qE "^${component}\|" "$CATALOG"; then
      docs="services/${component}/docs/SERVICE_CHARTER.md"
    elif [[ "$component" == frontend-* ]]; then
      docs="frontend/${component#frontend-}/docs/SERVICE_CHARTER.md"
    else
      docs="CLAUDE.md"
    fi
  fi
  load_style "$type"
  width=$((S_WIDTH - ${#S_PREFIX} - LABEL_WIDTH))
  [ "$width" -ge 20 ] || die "style '${type}' leaves less than 20 columns for values"
  {
    echo "SPDX-License-Identifier: MIT"
    echo "Copyright (c) 2026 AaaS Contributors"
    echo
    field "Component:       " "$component" "$width"
    field "Module:          " "$module" "$width"
    field "Owning Team:     " "${team} (${abbr})" "$width"
    field "Classification:  " "$classification" "$width"
    field "Purpose:         " "$purpose" "$width"
    field "Related Docs:    " "$docs" "$width"
  } | comment
}

# generate_into <dir>: write <type>.tmpl for every style into <dir>.
generate_into() {
  local type
  while IFS='|' read -r type _; do
    load_style "$type"
    comment <"$CANONICAL" >"${1}/${type}.tmpl"
  done < <(style_rows)
}

# check: fail when templates/headers/*.tmpl differ from a fresh generation.
check() {
  local tmp status=0
  tmp="$(mktemp -d)"
  generate_into "$tmp"
  if ! diff -r -x '*.psv' -x '*.txt' -x '*.md' "$tmp" "$HEADERS_DIR" >/dev/null; then
    diff -r -x '*.psv' -x '*.txt' -x '*.md' "$tmp" "$HEADERS_DIR" >&2 || true
    echo "error: templates/headers/*.tmpl are stale; run scripts/file-header.sh generate" >&2
    status=1
  fi
  rm -rf "$tmp"
  return "$status"
}

# main <command> [args]: dispatch to the sub-commands listed in Usage.
main() {
  [ $# -ge 1 ] || usage
  local command="$1"
  shift
  case "$command" in
    render) render "$@" ;;
    detect) [ $# -eq 1 ] || usage; detect_type "$1" || die "no header type known for '${1}'" ;;
    list) style_rows | awk -F'|' '{printf "%-12s %s\n", $1, $2}' ;;
    generate) rm -f "${HEADERS_DIR}"/*.tmpl; generate_into "$HEADERS_DIR" ;;
    check) check ;;
    -h | --help | help) usage ;;
    *) die "unknown command: ${command}" ;;
  esac
}

main "$@"
