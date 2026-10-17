# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/events
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Decodes aaas.addition.requested.v1 and encodes
#                  aaas.ledger.appended.v1.
# Related Docs:    contracts/events/, ADR-0013, CLAUDE.md 4.2

## The events the ledger consumes and produces.
##
## **Description:** Decoding is tolerant (unknown fields are ignored, as
## ADR-0013 asks of consumers) but checks every field the ledger relies on.
## Encoding produces exactly the closed schema of
## `aaas.ledger.appended.v1`.
##
## **Business Justification:** The ledger records only additions that are
## well formed, and announces each entry in the agreed contract.
##
## **Thread Safety:** pure; safe.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[json, options]
import ids, trace

const
  requestedTopic* = "aaas.addition.requested.v1"
    ## Topic the ledger consumes.
    ##
    ## **Description:** `TEMPORARY(P3.4)`: from P3.4 the ledger consumes
    ## `aaas.result.voted.v1` instead.
    ##
    ## **Business Justification:** The source of the additions to count.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  appendedTopic* = "aaas.ledger.appended.v1"
    ## Topic the ledger publishes to.
    ##
    ## **Description:** One message per ledger entry, keyed by `taskId`.
    ##
    ## **Business Justification:** Consumed by stopwatch and billing.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  maxOperand* = 99_999
    ## Largest operand of an addition (CLAUDE.md 1).
    ##
    ## **Description:** The `operand` definition of the envelope.
    ##
    ## **Business Justification:** A larger operand is not a valid event.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

type
  AdditionRequested* = object
    ## A decoded `aaas.addition.requested.v1`.
    ##
    ## **Description:** The envelope fields the ledger needs and the
    ## operands.
    ##
    ## **Business Justification:** The input of one counting task.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    eventId*: string ## Event identifier (lowercase UUID).
    taskId*: string ## Task identifier (lowercase UUID).
    traceparent*: string ## The event's traceparent, or empty.
    a*: int64 ## First operand, 0..99 999.
    b*: int64 ## Second operand, 0..99 999 (the number of successor calls).

  LedgerEntry* = object
    ## One entry of the hash chain.
    ##
    ## **Description:** The payload of `aaas.ledger.appended.v1`, plus the
    ## task it belongs to.
    ##
    ## **Business Justification:** The unit of the immutable ledger.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    sequence*: int64 ## Position in the chain, from 1, without gaps.
    taskId*: string ## The task.
    a*: int64 ## First operand.
    b*: int64 ## Second operand.
    sum*: int64 ## The result, published as `result`.
    recordedAt*: string ## Recording timestamp in the fixed form.
    prevHash*: string ## Hash of the previous entry.
    hash*: string ## Hash of this entry (ADR-0013).

  DecodeError* = object of ValueError
    ## An event that cannot be processed.
    ##
    ## **Description:** The message names the first problem.
    ##
    ## **Business Justification:** Rejected events are logged and skipped
    ## (`TEMPORARY(P3.6)`: sent to the DLQ from P3.6).
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

proc field(node: JsonNode, name: string, kind: JsonNodeKind): JsonNode =
  ## The field `name` of `node`, which must have `kind`.
  ##
  ## **Description:** Helper of `decodeAdditionRequested`.
  ##
  ## **Business Justification:** One error message per missing field.
  ##
  ## **Parameters:**
  ## - `node`: a JSON object.
  ## - `name`: the field.
  ## - `kind`: the expected JSON kind.
  ##
  ## **Returns:** the field.
  ##
  ## **Errors:** `DecodeError` if absent or of another kind.
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
  if node.kind != JObject or not node.hasKey(name) or node[name].kind != kind:
    raise newException(DecodeError, name & ": expected a " & $kind)
  node[name]

proc operand(payload: JsonNode, name: string): int64 =
  ## An operand of the payload, checked against 0..99 999.
  ##
  ## **Description:** Helper of `decodeAdditionRequested`.
  ##
  ## **Business Justification:** The ledger counts only valid operands.
  ##
  ## **Parameters:**
  ## - `payload`: the payload object.
  ## - `name`: `a` or `b`.
  ##
  ## **Returns:** the operand.
  ##
  ## **Errors:** `DecodeError` if absent, not an integer or out of range.
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
  let v = field(payload, name, JInt).getBiggestInt
  if v < 0 or v > maxOperand:
    raise newException(DecodeError, "payload." & name & ": expected 0.." & $maxOperand)
  v

proc decodeAdditionRequested*(raw: string): AdditionRequested =
  ## Decodes and checks an `aaas.addition.requested.v1` message.
  ##
  ## **Description:** Requires `type`, `version` 1, lowercase UUIDs for
  ## `eventId` and `taskId`, and integer operands in 0..99 999. A
  ## `traceparent` that is not valid is dropped (a new trace starts).
  ##
  ## **Business Justification:** Only a well-formed addition becomes a
  ## counting task.
  ##
  ## **Parameters:**
  ## - `raw`: the message value.
  ##
  ## **Returns:** the decoded event.
  ##
  ## **Errors:** `DecodeError` for malformed JSON or any failed check.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(size of the message).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **See Also:** contracts/events/aaas.addition.requested.v1.schema.json.
  runnableExamples:
    let e = decodeAdditionRequested("""{"eventId":"018f3c2e-7b1a-7c3d-9f00-000000000001",
      "type":"aaas.addition.requested","version":1,"taskId":"018f3c2e-7b1a-7c3d-9f00-0000000000aa",
      "payload":{"a":3,"b":2}}""")
    doAssert e.a == 3 and e.b == 2 and e.traceparent == ""
  var node: JsonNode
  try:
    node = parseJson(raw)
  except JsonParsingError, ValueError:
    raise newException(DecodeError, "not JSON")
  if field(node, "type", JString).getStr != "aaas.addition.requested":
    raise newException(DecodeError, "type: expected aaas.addition.requested")
  if field(node, "version", JInt).getInt != 1:
    raise newException(DecodeError, "version: expected 1")
  let eventId = field(node, "eventId", JString).getStr
  let taskId = field(node, "taskId", JString).getStr
  if not isUuid(eventId):
    raise newException(DecodeError, "eventId: expected a lowercase UUID")
  if not isUuid(taskId):
    raise newException(DecodeError, "taskId: expected a lowercase UUID")
  let payload = field(node, "payload", JObject)
  var tp = ""
  if node.hasKey("traceparent") and node["traceparent"].kind == JString and
      parseTraceparent(node["traceparent"].getStr).isSome:
    tp = node["traceparent"].getStr
  AdditionRequested(eventId: eventId, taskId: taskId, traceparent: tp,
      a: operand(payload, "a"), b: operand(payload, "b"))

proc ledgerAppended*(eventId: string, occurredAt: string, entry: LedgerEntry,
    span: TraceContext): string =
  ## Encodes an `aaas.ledger.appended.v1` event for `entry`.
  ##
  ## **Description:** The envelope in the order of `CLAUDE.md` 4.2 and the
  ## closed payload `sequence, a, b, result, recordedAt, prevHash, hash`.
  ##
  ## **Business Justification:** Announces the recorded result to
  ## stopwatch and billing, and lets cloud-notary verify the chain from the
  ## event alone (ADR-0013).
  ##
  ## **Parameters:**
  ## - `eventId`: a new lowercase UUIDv7.
  ## - `occurredAt`: the publication timestamp in the fixed form.
  ## - `entry`: the stored entry.
  ## - `span`: the span of the recording, for `traceparent`.
  ##
  ## **Returns:** the serialized event.
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
  ## **See Also:** contracts/events/aaas.ledger.appended.v1.schema.json.
  runnableExamples:
    import std/[json, strutils]
    import ledger/trace
    let span = TraceContext(traceId: 'a'.repeat(32), spanId: 'b'.repeat(16), flags: "01")
    let e = LedgerEntry(sequence: 1, taskId: "t", a: 3, b: 2, sum: 5)
    doAssert parseJson(ledgerAppended("e", "o", e, span))["payload"]["result"].getInt == 5
  $(%*{
    "eventId": eventId,
    "type": "aaas.ledger.appended",
    "version": 1,
    "occurredAt": occurredAt,
    "producer": "ledger",
    "taskId": entry.taskId,
    "traceparent": renderTraceparent(span),
    "payload": {
      "sequence": entry.sequence,
      "a": entry.a,
      "b": entry.b,
      "result": entry.sum,
      "recordedAt": entry.recordedAt,
      "prevHash": entry.prevHash,
      "hash": entry.hash
    }
  })
