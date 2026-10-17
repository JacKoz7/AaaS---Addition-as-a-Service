# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/logging
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Structured JSON log lines on stdout with the fields of
#                  CLAUDE.md 6.1.
# Related Docs:    CLAUDE.md 6.1, services/ledger/README.md

## Structured logging.
##
## **Description:** One JSON object per line with `ts`, `level`, `service`,
## `msg`, `taskId`, `traceId` and `spanId` (null when unknown), then extra
## fields, in this order. Lines below the minimum level are dropped. The
## service is single-threaded (one async event loop), so lines never
## interleave.
##
## **Business Justification:** The same log fields in all 28 languages, so
## Loki (P7.1) can follow a task across services.
##
## **Thread Safety:** not thread-safe; used from the event loop only.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[json, options, strutils]
import ids, trace

type
  Level* = enum
    ## Severity of a log line, from `lvDebug` (lowest) to `lvFatal`.
    ##
    ## **Description:** Ordered; the names are `debug` .. `fatal`.
    ##
    ## **Business Justification:** The level vocabulary shared by every
    ## AaaS service.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    lvDebug = "debug" ## Diagnostic detail, off by default.
    lvInfo = "info" ## Normal operation.
    lvWarn = "warn" ## Something unexpected that the service handled.
    lvError = "error" ## A failed operation.
    lvFatal = "fatal" ## The process cannot continue.

  Logger* = ref object
    ## A logger: service name, minimum level and output.
    ##
    ## **Description:** Built by `newLogger`; tests replace `sink`.
    ##
    ## **Business Justification:** Passed explicitly instead of global
    ## state.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    service*: string ## The `service` field of every line.
    minLevel*: Level ## Lines below this level are dropped.
    sink*: proc(line: string) {.closure.} ## Writes one complete line.

proc parseLevel*(name: string): Option[Level] =
  ## Reads a level name, case-insensitively.
  ##
  ## **Description:** Inverse of `$`.
  ##
  ## **Business Justification:** The `AAAS_LOG_LEVEL` variable.
  ##
  ## **Parameters:**
  ## - `name`: a level name.
  ##
  ## **Returns:** the level, if known.
  ##
  ## **Errors:** `none` for an unknown name.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    import std/options
    doAssert parseLevel("WARN") == some(lvWarn)
    doAssert parseLevel("loud").isNone
  for l in Level:
    if $l == name.toLowerAscii:
      return some(l)
  none(Level)

proc writeStdout(line: string) =
  ## Writes a line and a newline to stdout and flushes it.
  ##
  ## **Description:** The production sink.
  ##
  ## **Business Justification:** Logs go to stdout (CLAUDE.md 6.1).
  ##
  ## **Parameters:**
  ## - `line`: one rendered line.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** `IOError` if stdout is closed.
  ##
  ## **Side Effects:** writes to stdout.
  ##
  ## **Complexity:** O(size of the line).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  stdout.writeLine(line)
  stdout.flushFile()

proc newLogger*(service: string, minLevel: Level): Logger =
  ## Creates a logger writing to stdout.
  ##
  ## **Description:** Each line is followed by a newline and a flush.
  ##
  ## **Business Justification:** Logs go to stdout (CLAUDE.md 6.1).
  ##
  ## **Parameters:**
  ## - `service`: the service name.
  ## - `minLevel`: the minimum level.
  ##
  ## **Returns:** the logger.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **See Also:** `log`.
  runnableExamples:
    doAssert newLogger("ledger", lvInfo).service == "ledger"
  Logger(service: service, minLevel: minLevel, sink: writeStdout)

proc renderLine*(ts, service: string, level: Level, taskId: string,
    trace: Option[TraceContext], msg: string,
    extra: openArray[(string, JsonNode)] = []): string =
  ## Renders one log line.
  ##
  ## **Description:** The fixed fields in the order of CLAUDE.md 6.1, then
  ## the extra fields. An empty `taskId` is written as null.
  ##
  ## **Business Justification:** Separated from `log` for tests.
  ##
  ## **Parameters:**
  ## - `ts`: the timestamp text.
  ## - `service`: the service name.
  ## - `level`: the severity.
  ## - `taskId`: the task, or empty.
  ## - `trace`: the trace context, if any.
  ## - `msg`: the message.
  ## - `extra`: extra fields.
  ##
  ## **Returns:** the JSON line without a newline.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(size of the line).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **See Also:** `log`.
  runnableExamples:
    import std/options
    import ledger/trace
    doAssert renderLine("t", "ledger", lvInfo, "", none(TraceContext), "started") ==
      """{"ts":"t","level":"info","service":"ledger","msg":"started","taskId":null,"traceId":null,"spanId":null}"""
  let line = newJObject()
  line["ts"] = %ts
  line["level"] = %($level)
  line["service"] = %service
  line["msg"] = %msg
  line["taskId"] = (if taskId.len > 0: %taskId else: newJNull())
  if trace.isSome:
    line["traceId"] = %trace.get.traceId
    line["spanId"] = %trace.get.spanId
  else:
    line["traceId"] = newJNull()
    line["spanId"] = newJNull()
  for (k, v) in extra:
    line[k] = v
  $line

proc log*(logger: Logger, level: Level, msg: string, taskId = "",
    trace = none(TraceContext), extra: openArray[(string, JsonNode)] = []) =
  ## Writes one log line if its level is enabled.
  ##
  ## **Description:** Timestamps the line with the current time.
  ##
  ## **Business Justification:** The single logging entry point.
  ##
  ## **Parameters:**
  ## - `logger`: the logger.
  ## - `level`: the severity.
  ## - `msg`: the message.
  ## - `taskId`: the task, or empty.
  ## - `trace`: the trace context, if any.
  ## - `extra`: extra fields.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** whatever the sink raises.
  ##
  ## **Side Effects:** writes to the sink.
  ##
  ## **Complexity:** O(size of the line).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **See Also:** `renderLine`.
  runnableExamples:
    var lines: seq[string]
    let l = Logger(service: "ledger", minLevel: lvInfo, sink: proc(s: string) = lines.add(s))
    l.log(lvDebug, "dropped")
    l.log(lvInfo, "kept")
    doAssert lines.len == 1
  if level < logger.minLevel:
    return
  logger.sink(renderLine(formatTimestamp(nowMillis()), logger.service, level,
      taskId, trace, msg, extra))
