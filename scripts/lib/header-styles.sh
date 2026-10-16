#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/lib/header-styles.sh
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Shared functions reading templates/headers/styles.psv:
#                  list the header types, load the comment style of one
#                  type, and detect the type of a file from its name. Sourced
#                  by scripts/file-header.sh and scripts/doc-check.sh.
# Related Docs:    templates/headers/README.md, ADR-0007, ADR-0009
#
# The sourcing script must set ROOT (repository root) and define
# `die <message>`. Compatible with bash 3.2.

# The variables set here (AAAS_TEAMS, S_*) are read by the sourcing scripts.
# shellcheck disable=SC2034
# Path of the comment style table.
STYLES="${ROOT}/templates/headers/styles.psv"

# The eight teams of CLAUDE.md 6.5.1, exactly as written in `Owning Team:`.
AAAS_TEAMS="Arithmetic Excellence Center (AEC)
Transaction Integrity Office (TIO)
Platform Enablement Guild (PEG)
Trust & Identity Board (TIB)
Customer Experience Tribe (CXT)
Revenue Operations Unit (ROU)
Cloud Governance Committee (CGC)
Observability Steering Group (OSG)"

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
