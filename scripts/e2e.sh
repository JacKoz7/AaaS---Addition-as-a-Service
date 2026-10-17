#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          scripts/e2e.sh
# Owning Team:     Customer Experience Tribe (CXT)
# Classification:  INTERNAL
# Purpose:         Runs the end-to-end tests (tests/e2e) in the Playwright
#                  image against the running system, through the gateway.
#                  Called by `make e2e`.
# Related Docs:    tests/e2e/README.md, CLAUDE.md 6.4, ADR-0019
#
# Usage:
#   scripts/e2e.sh [PLAYWRIGHT ARGS...]   e.g. scripts/e2e.sh -g "2 \+ 3"
#
# Requires `make up` first: the gateway must be healthy. The tests run in a
# container on the Compose network `aaas-public` and open
# http://gateway:8000/, the gateway's entry point inside that network (the
# host's 127.0.0.1:80 is not reachable from containers). The HTML report and
# the traces of failed tests are written to build/e2e/.
#
# Environment:
#   AAAS_E2E_NETWORK   network of the gateway (default aaas-public)
#   AAAS_BASE_URL      URL of the gateway in that network
#                      (default http://gateway:8000/)
#
# Exit status: that of Playwright (0 when every test passed); 2 when the
# gateway is not running.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NETWORK="${AAAS_E2E_NETWORK:-aaas-public}"
BASE_URL="${AAAS_BASE_URL:-http://gateway:8000/}"
IMAGE="aaas/e2e:dev"
RESULTS="${ROOT}/build/e2e"

# gateway_healthy: succeed if the gateway container reports healthy.
gateway_healthy() {
  local id
  id="$(docker ps --quiet --filter "network=${NETWORK}" --filter "label=com.docker.compose.service=gateway")"
  [ -n "$id" ] && [ "$(docker inspect --format '{{.State.Health.Status}}' "$id")" = "healthy" ]
}

if ! gateway_healthy; then
  echo "error: the gateway is not running and healthy on ${NETWORK}; start the system with: make up" >&2
  exit 2
fi

echo "==> building ${IMAGE}"
docker build --quiet --tag "$IMAGE" "${ROOT}/tests/e2e" >/dev/null

rm -rf "$RESULTS"
mkdir -p "$RESULTS"
chmod 0777 "$RESULTS"

echo "==> end-to-end tests against ${BASE_URL} (network ${NETWORK})"
status=0
docker run --rm --network "$NETWORK" --env "AAAS_BASE_URL=${BASE_URL}" \
  --volume "${RESULTS}:/results" "$IMAGE" "$@" || status=$?
echo "==> report: build/e2e/report/index.html"
exit "$status"
