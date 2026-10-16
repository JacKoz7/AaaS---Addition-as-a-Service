#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/ci/changed-components.sh
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Computes the set of components (services/<name> and
#                  frontend/<name> directories that have a Makefile) affected
#                  by a change, and prints it as a JSON array for the
#                  GitHub Actions build/test matrix.
# Related Docs:    .github/workflows/ci.yml, ADR-0006, ADR-0002
#
# Usage:
#   scripts/ci/changed-components.sh [BASE]
#
#   BASE  Git revision to diff HEAD against. Special values:
#         - empty or 40 zeros (GitHub's "no previous commit"): the merge base
#           with origin/main is used; if that cannot be found, or HEAD is
#           origin/main itself, every component is selected.
#         - "all": every component is selected.
#
# Output (stdout), one line each:
#   components=<JSON array of {"name","service","path"}>
#   count=<number of selected components>
# The lines are in GITHUB_OUTPUT format; when GITHUB_OUTPUT is set they are
# also appended to that file. Diagnostics go to stderr.
#
# Selection rules:
#   - A changed file under services/<name>/ or frontend/<name>/ selects that
#     component, if its Makefile still exists (deleted components are dropped).
#   - A changed file matching GLOBAL_PATHS selects every component, because
#     those files influence how every component is built or tested.

set -euo pipefail

# Path prefixes whose change affects every component (see ADR-0006).
GLOBAL_PATHS=(
  "Makefile"
  "docker-compose.yml"
  "templates/service/"
  "contracts/"
  ".github/workflows/ci.yml"
  "scripts/ci/"
)

# Zero object id that GitHub reports as `before` for a newly created branch.
ZERO_SHA="0000000000000000000000000000000000000000"

# all_components: print every component directory (services/* and frontend/*
# with a Makefile), one relative path per line, sorted.
all_components() {
  local makefile
  for makefile in services/*/Makefile frontend/*/Makefile; do
    if [ -e "$makefile" ]; then dirname "$makefile"; fi
  done | sort -u
}

# resolve_base <base>: print the revision to diff against, or "all" when every
# component must be selected. Reads origin/main if it is available.
resolve_base() {
  local base="$1" head merge_base
  if [ "$base" = "all" ]; then
    echo "all"
    return
  fi
  if [ -n "$base" ] && [ "$base" != "$ZERO_SHA" ] && git cat-file -e "${base}^{commit}" 2>/dev/null; then
    echo "$base"
    return
  fi
  head="$(git rev-parse HEAD)"
  if merge_base="$(git merge-base origin/main HEAD 2>/dev/null)" && [ "$merge_base" != "$head" ]; then
    echo "$merge_base"
    return
  fi
  echo "warning: no usable base revision ('${base}'); selecting every component." >&2
  echo "all"
}

# is_global <path>: succeed if <path> matches one of GLOBAL_PATHS.
is_global() {
  local path="$1" prefix
  for prefix in "${GLOBAL_PATHS[@]}"; do
    case "$path" in
      "$prefix" | "$prefix"*) return 0 ;;
    esac
  done
  return 1
}

# changed_components <base>: print the component directories touched by the
# diff <base>...HEAD, or every component when a global path changed.
changed_components() {
  local base="$1" path component
  local -a changed=()
  # A read loop instead of mapfile keeps the script working on bash 3.2 (macOS).
  while IFS= read -r path; do
    changed+=("$path")
  done < <(git diff --name-only "${base}...HEAD")
  [ "${#changed[@]}" -gt 0 ] || return 0
  for path in "${changed[@]}"; do
    if is_global "$path"; then
      echo "info: global path '${path}' changed; selecting every component." >&2
      all_components
      return
    fi
  done
  for path in "${changed[@]}"; do
    case "$path" in
      services/*/* | frontend/*/*)
        component="$(cut -d/ -f1-2 <<<"$path")"
        if [ -e "${component}/Makefile" ]; then echo "$component"; fi
        ;;
    esac
  done | sort -u
}

# to_json: read component directories from stdin and print the JSON array used
# as the matrix. `service` is the Compose service name: <name> for services,
# frontend-<name> for microfrontends (CLAUDE.md 6.2 and 7.1 naming).
to_json() {
  local dir name service first=1
  printf '['
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    name="${dir#*/}"
    case "$dir" in
      frontend/*) service="frontend-${name}" ;;
      *) service="$name" ;;
    esac
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{"name":"%s","service":"%s","path":"%s"}' "$name" "$service" "$dir"
  done
  printf ']\n'
}

# main [base]: compute the selection and emit it in GITHUB_OUTPUT format.
main() {
  local base selection json count
  base="$(resolve_base "${1:-}")"
  if [ "$base" = "all" ]; then
    selection="$(all_components)"
  else
    selection="$(changed_components "$base")"
  fi
  json="$(to_json <<<"$selection")"
  count="$(grep -c . <<<"$selection" || true)"
  {
    echo "components=${json}"
    echo "count=${count}"
  } | tee -a "${GITHUB_OUTPUT:-/dev/null}"
}

main "$@"
