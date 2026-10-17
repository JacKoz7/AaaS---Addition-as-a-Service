# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/config
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Configuration of the ledger service read from environment
#                  variables (bootstrap mode `env`).
# Related Docs:    services/ledger/README.md (Configuration), CLAUDE.md 3
#                  (platform at startup) and 6.1, ADR-0017

## Service configuration.
##
## **Description:** Until step P5.2 every service reads its configuration
## from environment variables (`AAAS_BOOTSTRAP=env`); `platform` is refused
## until config-server and OpenBao exist. The variables and defaults are
## listed in the README.
##
## **Business Justification:** No hard-coded hosts or passwords (CLAUDE.md
## 6.1).
##
## **Thread Safety:** pure; safe.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[options, strutils]
import logging

type
  Config* = object
    ## The configuration of one ledger process.
    ##
    ## **Description:** One field per environment variable, see the README.
    ##
    ## **Business Justification:** Everything the process needs to start.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    service*: string ## `AAAS_SERVICE`, default `ledger`.
    environment*: string ## `AAAS_ENV`, default `local`.
    httpPort*: int ## `AAAS_HTTP_PORT`, default `8080`.
    brokers*: string ## `AAAS_KAFKA_BROKERS`, default `redpanda:9092`.
    consumerGroup*: string ## `AAAS_CONSUMER_GROUP`, default `ledger`.
    dbUrl*: string ## `AAAS_DB_URL`, default `http://ledger-db:8080`.
    dbName*: string ## `AAAS_DB_NAME`, default `ledger`.
    dbUser*: string ## `AAAS_DB_USER`, default `ledger`.
    dbPassword*: string ## `LEDGER_DB_PASSWORD`, required (OpenBao in P5.3).
    migrationsDir*: string ## `AAAS_MIGRATIONS_DIR`, default `/app/migrations`.
    successorUrl*: string ## `AAAS_SUCCESSOR_URL`, default `http://successor:8080`.
    checkpointEvery*: int ## `AAAS_CHECKPOINT_EVERY`, default `1000` successor calls.
    logLevel*: Level ## `AAAS_LOG_LEVEL`, default `info`.
    kafkaLogLevel*: int ## `AAAS_KAFKA_LOG_LEVEL`, librdkafka 0..7, default `4`.

  Lookup* = proc(name: string): Option[string] {.closure.}
    ## Returns the value of an environment variable, if set.
    ##
    ## **Description:** `std/envvars` in production, a table in tests.
    ##
    ## **Business Justification:** Testability of `loadConfig`.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

  ConfigError* = object of ValueError
    ## A missing or malformed configuration value.
    ##
    ## **Description:** The message names the variable.
    ##
    ## **Business Justification:** A mistake stops the process with a
    ## clear message.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

proc intIn(value, name: string, lo, hi: int): int =
  ## Parses an integer variable and checks its range.
  ##
  ## **Description:** Helper of `loadConfig`.
  ##
  ## **Business Justification:** Every numeric variable is validated.
  ##
  ## **Parameters:**
  ## - `value`: the text.
  ## - `name`: the variable, for the message.
  ## - `lo`, `hi`: the inclusive range.
  ##
  ## **Returns:** the number.
  ##
  ## **Errors:** `ConfigError` if not a number in `lo..hi`.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(length of the value).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  try:
    result = parseInt(value)
  except ValueError:
    raise newException(ConfigError, name & ": expected a number in " & $lo &
        ".." & $hi)
  if result < lo or result > hi:
    raise newException(ConfigError, name & ": expected a number in " & $lo &
        ".." & $hi)

proc loadConfig*(lookup: Lookup): Config =
  ## Reads the configuration from a variable lookup.
  ##
  ## **Description:** Empty values count as unset. `AAAS_BOOTSTRAP` must be
  ## `env` (the default).
  ##
  ## **Business Justification:** One validated configuration at startup.
  ##
  ## **Parameters:**
  ## - `lookup`: returns the value of a variable.
  ##
  ## **Returns:** the configuration.
  ##
  ## **Errors:** `ConfigError` for `AAAS_BOOTSTRAP=platform` or another
  ## mode, a missing `LEDGER_DB_PASSWORD`, a port outside 1..65535, an
  ## unknown log level, a Kafka log level outside 0..7 or a checkpoint
  ## interval outside 1..100000.
  ##
  ## **Side Effects:** None of its own (the lookup is the caller's).
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **See Also:** README, section Configuration.
  runnableExamples:
    import std/options
    let cfg = loadConfig(proc(n: string): Option[string] =
      if n == "LEDGER_DB_PASSWORD": some("x") else: none(string))
    doAssert cfg.successorUrl == "http://successor:8080"
    doAssert cfg.checkpointEvery == 1000
  proc get(name, default: string): string =
    let v = lookup(name)
    if v.isSome and v.get.len > 0: v.get else: default
  case get("AAAS_BOOTSTRAP", "env")
  of "env": discard
  of "platform":
    raise newException(ConfigError, "AAAS_BOOTSTRAP=platform is not available yet: config-server and OpenBao arrive in steps P5.2 and P5.3; use AAAS_BOOTSTRAP=env")
  else:
    raise newException(ConfigError, "AAAS_BOOTSTRAP: expected env or platform, got " &
        get("AAAS_BOOTSTRAP", ""))
  let level = parseLevel(get("AAAS_LOG_LEVEL", "info"))
  if level.isNone:
    raise newException(ConfigError, "AAAS_LOG_LEVEL: expected debug, info, warn, error or fatal")
  let password = get("LEDGER_DB_PASSWORD", "")
  if password.len == 0:
    raise newException(ConfigError, "LEDGER_DB_PASSWORD is required")
  Config(
    service: get("AAAS_SERVICE", "ledger"),
    environment: get("AAAS_ENV", "local"),
    httpPort: intIn(get("AAAS_HTTP_PORT", "8080"), "AAAS_HTTP_PORT", 1, 65535),
    brokers: get("AAAS_KAFKA_BROKERS", "redpanda:9092"),
    consumerGroup: get("AAAS_CONSUMER_GROUP", "ledger"),
    dbUrl: get("AAAS_DB_URL", "http://ledger-db:8080").strip(leading = false,
        chars = {'/'}),
    dbName: get("AAAS_DB_NAME", "ledger"),
    dbUser: get("AAAS_DB_USER", "ledger"),
    dbPassword: password,
    migrationsDir: get("AAAS_MIGRATIONS_DIR", "/app/migrations"),
    successorUrl: get("AAAS_SUCCESSOR_URL", "http://successor:8080").strip(
        leading = false, chars = {'/'}),
    checkpointEvery: intIn(get("AAAS_CHECKPOINT_EVERY", "1000"),
        "AAAS_CHECKPOINT_EVERY", 1, 100_000),
    logLevel: level.get,
    kafkaLogLevel: intIn(get("AAAS_KAFKA_LOG_LEVEL", "4"),
        "AAAS_KAFKA_LOG_LEVEL", 0, 7))
