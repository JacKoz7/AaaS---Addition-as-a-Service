#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          immudb/provision.sh
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         One-shot provisioning of the ledger database: creates the
#                  immudb database and the ledger's read-write user with the
#                  superadmin credentials, so that the service itself never
#                  holds them. Idempotent.
# Related Docs:    services/ledger/README.md (Database), ADR-0017,
#                  compose/services.yml (ledger-db-init)
#
# Runs in the `ledger-db-init` container (curlimages/curl, BusyBox sh) after
# `ledger-db` is healthy, and in `make test` against a throw-away immudb.
#
# Environment:
#   IMMUDB_URL              immudb web server (default http://ledger-db:8080)
#   IMMUDB_ADMIN_PASSWORD   password of the superadmin `immudb` (required)
#   LEDGER_DB_NAME          database to create (default ledger)
#   LEDGER_DB_USER          user to create (default ledger)
#   LEDGER_DB_PASSWORD      password of that user (required)
#
# An existing database or user is left as it is: changing LEDGER_DB_PASSWORD
# later does not change the stored password (see the RUNBOOK).
#
# Exit status: 0 when the database and the user exist, 1 otherwise.

set -eu

url="${IMMUDB_URL:-http://ledger-db:8080}"
admin_password="${IMMUDB_ADMIN_PASSWORD:?IMMUDB_ADMIN_PASSWORD is required}"
db="${LEDGER_DB_NAME:-ledger}"
user="${LEDGER_DB_USER:-ledger}"
password="${LEDGER_DB_PASSWORD:?LEDGER_DB_PASSWORD is required}"

# b64 <text>: base64 of the text on one line (immudb's REST API expects
# user names and passwords base64-encoded).
b64() {
  printf %s "$1" | base64 | tr -d '\n'
}

# log <message>: one JSON log line on stdout (CLAUDE.md 6.1).
log() {
  printf '{"ts":"%s","level":"info","service":"ledger-db-init","msg":"%s","taskId":null,"traceId":null,"spanId":null}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" "$1"
}

# fail <message>: log an error and exit 1.
fail() {
  printf '{"ts":"%s","level":"error","service":"ledger-db-init","msg":"%s","taskId":null,"traceId":null,"spanId":null}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" "$1"
  exit 1
}

i=0
until curl -fsS --max-time 2 "${url}/api/health" >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -lt 60 ] || fail "immudb at ${url} did not answer within 60 s"
  sleep 1
done

answer="$(curl -sS --max-time 5 -X POST "${url}/api/login" \
  -d "{\"user\":\"$(b64 immudb)\",\"password\":\"$(b64 "$admin_password")\"}")"
token="$(printf %s "$answer" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
[ -n "$token" ] || fail "superadmin login failed"

answer="$(curl -sS --max-time 5 -X POST "${url}/api/db/create/v2" \
  -H "Authorization: Bearer ${token}" -d "{\"name\":\"${db}\"}")"
case "$answer" in
  *'"settings"'*) log "database ${db} created" ;;
  *'database already exists'*) log "database ${db} already exists" ;;
  *) fail "creating database ${db} failed" ;;
esac

# permission 2 = read-write on the database (immudb's PERMISSION_RW).
answer="$(curl -sS --max-time 5 -X POST "${url}/api/user" \
  -H "Authorization: Bearer ${token}" \
  -d "{\"user\":\"$(b64 "$user")\",\"password\":\"$(b64 "$password")\",\"database\":\"${db}\",\"permission\":2}")"
case "$answer" in
  '{}') log "user ${user} created with read-write permission on ${db}" ;;
  *'user already exists'*) log "user ${user} already exists" ;;
  *) fail "creating user ${user} failed" ;;
esac
