#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          infra/redpanda/create-topics.sh
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Creates every topic of contracts/events/topics.psv on the
#                  Redpanda broker and brings existing topics to the declared
#                  partition count and configuration; with --check, only
#                  verifies that they are in that state.
# Related Docs:    CLAUDE.md (section 4.2), ADR-0011, infra/redpanda/README.md,
#                  contracts/events/topics.psv
#
# Usage:
#   create-topics.sh            create missing topics, reconcile existing ones
#   create-topics.sh --check    verify only; exit 1 if any topic differs
#
# Runs inside the one-shot Compose service `redpanda-topics` (image of the
# broker, which ships rpk), started by `make up` after the broker is healthy,
# and on demand by `make topics` / `make topics-check`.
#
# Environment:
#   RPK_BROKERS   Kafka API address of the broker (default: redpanda:9092);
#                 read by rpk itself.
#   RPK_ADMIN_HOSTS
#                 Admin API address of the broker, used for the health check
#                 (default: redpanda:9644); read by rpk itself.
#   TOPICS_FILE   path of the topic registry (default: topics.psv next to
#                 this script, where Compose mounts it).
#
# Every topic gets the same configuration (ADR-0011): replication factor 1
# (a single broker), cleanup.policy=delete and seven days of retention. The
# script is idempotent: a second run changes nothing and exits 0. It never
# deletes a topic and never lowers a partition count (Redpanda cannot).
#
# Exit status: 0 on success, 1 when a topic cannot be reconciled or (with
# --check) differs from the registry, 2 on usage or registry errors.

set -euo pipefail

# Replication factor of every topic: the local cluster has one broker.
REPLICAS=1

# Topic-level configuration applied to every topic (ADR-0011).
TOPIC_CONFIG=(cleanup.policy=delete retention.ms=604800000)

# Seconds to wait for the broker before giving up.
BROKER_TIMEOUT=60

export RPK_BROKERS="${RPK_BROKERS:-redpanda:9092}"
export RPK_ADMIN_HOSTS="${RPK_ADMIN_HOSTS:-redpanda:9644}"
TOPICS_FILE="${TOPICS_FILE:-$(dirname "$0")/topics.psv}"

# usage: print the usage block of this file and exit with status 2.
usage() {
  sed -n '/^# Usage:/,/^# --check/p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

# die <message>: print an error to stderr and exit with status 2.
die() {
  echo "error: $*" >&2
  exit 2
}

# log <message>: print a progress line on stdout.
log() {
  echo "topics: $*"
}

# registry: print `topic partitions` for every data row of TOPICS_FILE and
# fail on a malformed row (bad name, non-positive partitions, wrong column
# count) or a duplicate topic.
registry() {
  awk -F'|' '
    /^#/ || /^[[:space:]]*$/ { next }
    NF != 5 { printf "error: %s:%d: expected 5 columns, got %d\n", FILENAME, FNR, NF > "/dev/stderr"; bad = 1; next }
    $1 !~ /^aaas\.[a-z]+(\.[a-z-]+)*\.v[0-9]+$/ { printf "error: %s:%d: invalid topic name %s\n", FILENAME, FNR, $1 > "/dev/stderr"; bad = 1; next }
    $2 !~ /^[1-9][0-9]*$/ { printf "error: %s:%d: invalid partition count %s\n", FILENAME, FNR, $2 > "/dev/stderr"; bad = 1; next }
    seen[$1]++ { printf "error: %s:%d: duplicate topic %s\n", FILENAME, FNR, $1 > "/dev/stderr"; bad = 1; next }
    { print $1, $2 }
    END { exit bad }
  ' "$TOPICS_FILE"
}

# wait_for_broker: poll the broker until it reports a healthy cluster, for at
# most BROKER_TIMEOUT seconds.
wait_for_broker() {
  local waited=0
  until rpk cluster health 2>/dev/null | grep -qE '^Healthy:[[:space:]]+true'; do
    [ "$waited" -lt "$BROKER_TIMEOUT" ] || { echo "error: broker ${RPK_BROKERS} not healthy after ${BROKER_TIMEOUT}s" >&2; exit 1; }
    sleep 1
    waited=$((waited + 1))
  done
}

# existing_partitions: print `topic partitions` for every topic on the
# broker (internal topics excluded).
existing_partitions() {
  rpk topic list | awk 'NR > 1 { print $1, $2 }'
}

# config_value <topic> <key>: print the current value of a topic config key.
config_value() {
  rpk topic describe "$1" --print-configs | awk -v key="$2" '$1 == key { print $2 }'
}

# config_drift <topic>: print every `key=value` of TOPIC_CONFIG that differs
# from the topic's current configuration.
config_drift() {
  local setting
  for setting in "${TOPIC_CONFIG[@]}"; do
    [ "$(config_value "$1" "${setting%%=*}")" = "${setting#*=}" ] || echo "$setting"
  done
}

# reconcile <topic> <partitions> <current>: create the topic when <current>
# is empty, otherwise raise its partition count and fix its configuration.
reconcile() {
  local topic="$1" want="$2" have="$3" setting
  local -a set_args=() drift=()
  for setting in "${TOPIC_CONFIG[@]}"; do set_args+=(--topic-config "$setting"); done
  if [ -z "$have" ]; then
    rpk topic create "$topic" --partitions "$want" --replicas "$REPLICAS" "${set_args[@]}" >/dev/null
    log "created ${topic} (${want} partitions)"
    return 0
  fi
  if [ "$have" -gt "$want" ]; then
    echo "error: ${topic} has ${have} partitions, the registry declares ${want}; partitions cannot be removed" >&2
    return 1
  fi
  if [ "$have" -lt "$want" ]; then
    rpk topic add-partitions "$topic" --num $((want - have)) >/dev/null
    log "${topic}: partitions ${have} -> ${want}"
  fi
  while IFS= read -r setting; do drift+=("$setting"); done < <(config_drift "$topic")
  if [ "${#drift[@]}" -gt 0 ]; then
    set_args=()
    for setting in "${drift[@]}"; do set_args+=(--set "$setting"); done
    rpk topic alter-config "$topic" "${set_args[@]}" >/dev/null
    log "${topic}: set ${drift[*]}"
  fi
  log "${topic} ok"
}

# verify <topic> <partitions> <current>: report whether the topic exists with
# the declared partition count and configuration; return 1 if not.
verify() {
  local topic="$1" want="$2" have="$3" drift
  if [ -z "$have" ]; then
    echo "missing: ${topic}" >&2
    return 1
  fi
  if [ "$have" != "$want" ]; then
    echo "differs: ${topic} has ${have} partitions, expected ${want}" >&2
    return 1
  fi
  drift="$(config_drift "$topic")"
  if [ -n "$drift" ]; then
    echo "differs: ${topic} config, expected $(echo "$drift" | tr '\n' ' ')" >&2
    return 1
  fi
  log "${topic} ok"
}

# main [--check]: reconcile (default) or verify every registry topic.
main() {
  local mode=reconcile rows current topic want have failed=0
  case "${1:-}" in
    "") ;;
    --check) mode=verify ;;
    *) usage ;;
  esac
  [ $# -le 1 ] || usage
  [ -r "$TOPICS_FILE" ] || die "topic registry ${TOPICS_FILE} not readable"
  rows="$(registry)" || exit 2
  [ -n "$rows" ] || die "topic registry ${TOPICS_FILE} has no topics"

  wait_for_broker
  current="$(existing_partitions)"
  while read -r topic want; do
    have="$(awk -v t="$topic" '$1 == t { print $2 }' <<<"$current")"
    "$mode" "$topic" "$want" "$have" || failed=1
  done <<<"$rows"

  if [ "$failed" -ne 0 ]; then
    echo "error: topics differ from ${TOPICS_FILE}" >&2
    exit 1
  fi
  log "$(wc -l <<<"$rows" | tr -d ' ') topics match ${TOPICS_FILE}"
}

main "$@"
