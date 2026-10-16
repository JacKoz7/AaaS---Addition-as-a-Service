#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/changelog.sh
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Generates the changelog section of one component with
#                  git-cliff (cliff.toml) from the commits whose scope is the
#                  component: prints the unreleased changes, or inserts a new
#                  version under `## [Unreleased]` of its CHANGELOG.md.
# Related Docs:    CLAUDE.md (6.5.8, 7.1), ADR-0010, cliff.toml,
#                  docs/governance/RELEASE_PROCESS.md
#
# Usage:
#   scripts/changelog.sh <component>            print the unreleased changes
#   scripts/changelog.sh <component> <X.Y.Z>    insert version X.Y.Z into
#                                               <dir>/docs/CHANGELOG.md
#
# <component> is a directory name in services/ or frontend/. The commit scope
# and the release tag prefix are the service name, or `frontend-<name>` for a
# microfrontend (CLAUDE.md 7.1): commits since the last tag `<scope>/vX.Y.Z`
# are the unreleased ones. git-cliff runs from its pinned Docker image.
# The generated section ends with an empty "Business Impact" heading that is
# written by hand before the release commit.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Pinned git-cliff image (multi-arch); see ADR-0010.
GIT_CLIFF_IMAGE="orhunp/git-cliff:2.14.2"

# usage: print the usage block of this file and exit with status 2.
usage() {
  sed -n '/^# Usage:/,/^# written by hand/p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

# die <message>: print an error to stderr and exit with status 1.
die() { echo "error: $*" >&2; exit 1; }

# cliff <args...>: run git-cliff on the repository with AAAS_SCOPE and the
# tag pattern of the component; the generated section goes to stdout.
cliff() {
  docker run --rm --user "$(id -u):$(id -g)" \
    --volume "${ROOT}:/app" --workdir /app \
    --env AAAS_SCOPE="$SCOPE" --env RUST_LOG=warn --env GIT_CONFIG_COUNT=1 \
    --env GIT_CONFIG_KEY_0=safe.directory --env GIT_CONFIG_VALUE_0=/app \
    "$GIT_CLIFF_IMAGE" --config cliff.toml --tag-pattern "^${SCOPE}/v[0-9]" \
    --unreleased --strip all "$@"
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage
NAME="$1"
VERSION="${2:-}"

if [ -d "${ROOT}/services/${NAME}" ]; then
  DIR="services/${NAME}"; SCOPE="$NAME"
elif [ -d "${ROOT}/frontend/${NAME}" ]; then
  DIR="frontend/${NAME}"; SCOPE="frontend-${NAME}"
else
  die "no services/${NAME} or frontend/${NAME} directory"
fi

if [ -z "$VERSION" ]; then
  cliff
  exit 0
fi

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z (SemVer): '$VERSION'"
FILE="${ROOT}/${DIR}/docs/CHANGELOG.md"
[ -f "$FILE" ] || die "${DIR}/docs/CHANGELOG.md not found"
grep -q '^## \[Unreleased\]' "$FILE" || die "${DIR}/docs/CHANGELOG.md has no '## [Unreleased]' heading"
if grep -qF "## [${VERSION}]" "$FILE"; then
  die "${DIR}/docs/CHANGELOG.md already has a section for ${VERSION}"
fi
git -C "$ROOT" rev-parse -q --verify "refs/tags/${SCOPE}/v${VERSION}" >/dev/null \
  && die "tag ${SCOPE}/v${VERSION} already exists"

SECTION="$(cliff --tag "${SCOPE}/v${VERSION}")"
[ -n "$SECTION" ] || die "git-cliff produced no output"

# Insert the section after the Unreleased heading, separated by blank lines.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
SECTION="$SECTION" awk '
  !done && /^## \[Unreleased\]/ { print; print ""; print ENVIRON["SECTION"]; done = 1; next }
  { print }
' "$FILE" > "$TMP"
cat "$TMP" > "$FILE"
echo "inserted ${VERSION} into ${DIR}/docs/CHANGELOG.md; write the Business Impact section before committing."
