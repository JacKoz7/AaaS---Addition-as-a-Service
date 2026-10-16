#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/doc-check.sh
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Language-independent documentation check (CLAUDE.md 6.5.4,
#                  "remaining languages"): every file starts with the
#                  mandatory header in its comment syntax, and every
#                  top-level definition of the types listed in
#                  scripts/lib/doc-definitions.psv is preceded by a comment.
#                  Prints the coverage per component and fails below 100%.
# Related Docs:    CLAUDE.md (6.5.2, 6.5.4), ADR-0009, .doc-check-ignore,
#                  templates/headers/styles.psv
#
# Usage:
#   scripts/doc-check.sh [--quiet] [FILE...]
#
#   Without FILE, checks every tracked and untracked, not git-ignored file.
#   With FILE (as pre-commit passes them), checks only those files.
#   --quiet prints only the problems and the total line.
#
# Exit status: 0 when coverage is 100%, 1 otherwise, 2 on usage errors.
#
# Header rules (checked against the style of the file's type):
#   - an optional preamble (shebang, `#lang`, `<?php`, magic comment) and
#     blank lines may come first, then the block opener of the style, if any;
#   - the next lines are `SPDX-License-Identifier: MIT` and
#     `Copyright (c) <year> AaaS Contributors`, with the style's prefix;
#   - then, within the first HEADER_WINDOW lines and in this order, the
#     fields Component, Module, Owning Team, Classification, Purpose and
#     Related Docs, each non-empty; Owning Team is one of the eight teams of
#     CLAUDE.md 6.5.1 and Classification is PUBLIC, INTERNAL or CONFIDENTIAL.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IGNORE_FILE="${ROOT}/.doc-check-ignore"
DEFINITIONS="${ROOT}/scripts/lib/doc-definitions.psv"

# Number of lines at the top of a file in which the header must be complete.
HEADER_WINDOW=40

# Header fields in their mandatory order.
FIELDS="Component Module Owning_Team Classification Purpose Related_Docs"

# die <message>: print an error to stderr and exit with status 2.
die() {
  echo "error: $*" >&2
  exit 2
}

# shellcheck source=scripts/lib/header-styles.sh
. "${ROOT}/scripts/lib/header-styles.sh"

# problem <file> <message>: record one documentation defect on stdout of
# the check (collected by main) in the form `<file>: <message>`.
problem() {
  echo "PROBLEM|$1: $2"
}

# is_ignored <path>: succeed if <path> matches a pattern of .doc-check-ignore.
is_ignored() {
  local pattern
  while IFS= read -r pattern; do
    case "$pattern" in '' | '#'*) continue ;; esac
    # shellcheck disable=SC2254 # the pattern is a glob on purpose
    case "$1" in $pattern) return 0 ;; esac
  done <"$IGNORE_FILE"
  return 1
}

# component_of <path>: print the component a file belongs to:
# services/<name>, frontend/<name>, or `repo` for everything else.
component_of() {
  case "$1" in
    services/*/* | frontend/*/*) cut -d/ -f1-2 <<<"$1" ;;
    *) echo "repo" ;;
  esac
}

# check_header <file> <type>: print PROBLEM lines for every header defect of
# <file>, using the comment style of <type>. Prints nothing when valid.
check_header() {
  local file="$1" i=0 n line field label value want expected_label
  local -a lines=()
  load_style "$2"
  while IFS= read -r line || [ -n "$line" ]; do
    lines+=("$line")
  done < <(head -n "$HEADER_WINDOW" "$file")
  n="${#lines[@]}"

  # Optional preamble and blank lines, then the block opener.
  if [ "$n" -gt 0 ] && [ -n "$S_PREAMBLE" ]; then
    case "${lines[0]}" in
      '#!'* | '#lang '* | "$S_PREAMBLE") i=1 ;;
    esac
  fi
  while [ "$i" -lt "$n" ] && [ -z "${lines[$i]}" ]; do i=$((i + 1)); done
  if [ -n "$S_OPEN" ]; then
    if [ "$i" -ge "$n" ] || [ "${lines[$i]}" != "$S_OPEN" ]; then
      problem "$file" "header: expected '${S_OPEN}' to open the header comment (type ${2})"
      return
    fi
    i=$((i + 1))
  fi

  # Licence and copyright lines.
  if [ "$i" -ge "$n" ] || [ "${lines[$i]}" != "${S_PREFIX}SPDX-License-Identifier: MIT" ]; then
    problem "$file" "header: line $((i + 1)) must be '${S_PREFIX}SPDX-License-Identifier: MIT' (type ${2})"
    return
  fi
  i=$((i + 1))
  if [ "$i" -ge "$n" ] || ! [[ "${lines[$i]}" =~ ^"${S_PREFIX}"Copyright\ \(c\)\ 20[0-9]{2}\ AaaS\ Contributors$ ]]; then
    problem "$file" "header: line $((i + 1)) must be '${S_PREFIX}Copyright (c) <year> AaaS Contributors'"
    return
  fi
  i=$((i + 1))

  # Fields, in order, each with a non-empty value.
  for field in $FIELDS; do
    label="${field//_/ }:"
    expected_label="${S_PREFIX}${label}"
    while [ "$i" -lt "$n" ] && [[ "${lines[$i]}" != "$expected_label"* ]]; do i=$((i + 1)); done
    if [ "$i" -ge "$n" ]; then
      problem "$file" "header: missing '${expected_label}' (in order, within the first ${HEADER_WINDOW} lines)"
      return
    fi
    value="${lines[$i]#"$expected_label"}"
    value="${value#"${value%%[! ]*}"}"
    if [ -z "$value" ]; then
      problem "$file" "header: '${label}' is empty"
    fi
    case "$field" in
      Owning_Team)
        want=0
        while IFS= read -r line; do [ "$value" = "$line" ] && want=1; done <<<"$AAAS_TEAMS"
        [ "$want" -eq 1 ] || problem "$file" "header: unknown team '${value}' (CLAUDE.md 6.5.1)"
        ;;
      Classification)
        case "$value" in
          PUBLIC | INTERNAL | CONFIDENTIAL) ;;
          *) problem "$file" "header: classification '${value}' is not PUBLIC, INTERNAL or CONFIDENTIAL" ;;
        esac
        ;;
    esac
    i=$((i + 1))
  done
}

# check_definitions <file> <type>: print `DEFS|<total>|<documented>` for
# <file> and one PROBLEM line per undocumented definition; prints
# `DEFS|0|0` when the type has no row in doc-definitions.psv.
check_definitions() {
  local file="$1" row
  row="$(grep -E "^${2}\|" "$DEFINITIONS" || true)"
  if [ -z "$row" ]; then
    echo "DEFS|0|0"
    return
  fi
  IFS='|' read -r _ DEF_RE COMMENT_RE SKIP_RE INLINE_RE <<<"$row"
  DEF_RE="$DEF_RE" COMMENT_RE="$COMMENT_RE" SKIP_RE="$SKIP_RE" INLINE_RE="$INLINE_RE" FILE="$file" \
    awk '
      BEGIN {
        def = ENVIRON["DEF_RE"]; com = ENVIRON["COMMENT_RE"]
        skip = ENVIRON["SKIP_RE"]; inl = ENVIRON["INLINE_RE"]; f = ENVIRON["FILE"]
        prev = ""; total = 0; documented = 0
      }
      $0 ~ def {
        total++
        if ((inl != "" && $0 ~ inl) || (prev != "" && prev ~ com)) {
          documented++
        } else {
          printf "PROBLEM|%s: line %d: definition without a preceding comment: %s\n", f, NR, $0
        }
      }
      { if (!(skip != "" && $0 ~ skip)) prev = $0 }
      END { printf "DEFS|%d|%d\n", total, documented }
    ' "$file"
}

# check_file <file>: print one `FILE|<component>|<header ok>|<defs>|<documented>`
# record and the PROBLEM lines of <file>.
check_file() {
  local file="$1" type out header_ok=1 defs
  if ! type="$(detect_type "$file")"; then
    echo "PROBLEM|${file}: no header type for this file name; add it to templates/headers/styles.psv or .doc-check-ignore"
    echo "FILE|$(component_of "$file")|0|0|0"
    return
  fi
  out="$(check_header "$file" "$type")"
  if [ -n "$out" ]; then
    header_ok=0
    echo "$out"
  fi
  defs="$(check_definitions "$file" "$type")"
  grep '^PROBLEM|' <<<"$defs" || true
  defs="$(grep '^DEFS|' <<<"$defs")"
  echo "FILE|$(component_of "$file")|${header_ok}|$(cut -d'|' -f2 <<<"$defs")|$(cut -d'|' -f3 <<<"$defs")"
}

# list_files: print every tracked and untracked, not git-ignored file.
list_files() {
  git -C "$ROOT" ls-files --cached --others --exclude-standard | sort -u
}

# report: read the records of check_file on stdin, print the problems and the
# coverage table, and exit 1 if coverage is below 100%.
report() {
  QUIET="$1" awk -F'|' '
    $1 == "PROBLEM" { sub(/^PROBLEM\|/, ""); problems[++np] = $0; next }
    $1 == "FILE" {
      c = $2; files[c]++; hdr[c] += $3; defs[c] += $4; doc[c] += $5
      tf++; th += $3; td += $4; tdoc += $5
    }
    function pct(ok, all) { return all == 0 ? 100 : int(1000 * ok / all) / 10 }
    END {
      for (i = 1; i <= np; i++) print problems[i]
      if (np > 0) print ""
      if (ENVIRON["QUIET"] != "1") {
        printf "%-34s %15s %15s %9s\n", "Component", "Headers", "Definitions", "Coverage"
        n = 0; for (c in files) names[++n] = c
        for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (names[j] < names[i]) { t = names[i]; names[i] = names[j]; names[j] = t }
        for (i = 1; i <= n; i++) {
          c = names[i]
          printf "%-34s %15s %15s %8.1f%%\n", c, hdr[c] "/" files[c], doc[c] "/" defs[c], pct(hdr[c] + doc[c], files[c] + defs[c])
        }
      }
      printf "%-34s %15s %15s %8.1f%%\n", "TOTAL", th "/" tf, tdoc "/" td, pct(th + tdoc, tf + td)
      exit (np > 0 ? 1 : 0)
    }
  '
}

# main [--quiet] [file...]: check the given files, or every file.
main() {
  local quiet=0 file
  local -a files=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --quiet) quiet=1; shift ;;
      -h | --help) sed -n '/^# Usage:/,/^# Exit status/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
      --) shift; break ;;
      -*) die "unknown option: $1" ;;
      *) break ;;
    esac
  done
  cd "$ROOT"
  if [ $# -gt 0 ]; then
    files=("$@")
  else
    while IFS= read -r file; do files+=("$file"); done < <(list_files)
  fi
  for file in "${files[@]+"${files[@]}"}"; do
    [ -f "$file" ] || continue
    is_ignored "$file" && continue
    check_file "$file"
  done | report "$quiet"
}

main "$@"
