# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/trace
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Reads a W3C traceparent and derives the context of the
#                  span that continues it.
# Related Docs:    W3C Trace Context, CLAUDE.md 6.1, ADR-0013

## W3C Trace Context, version `00`.
##
## **Description:** `00-<32 hex trace-id>-<16 hex parent-id>-<2 hex flags>`,
## lowercase, non-zero identifiers. Work done for an event or a request is
## one span: same trace and flags as the caller, a new span identifier.
## Without a valid parent a new sampled trace starts.
##
## **Business Justification:** One trace per addition (CLAUDE.md 6.1,
## P7.2): the `traceparent` of published events, of successor calls and
## the `traceId` and `spanId` of log lines come from here.
##
## **Thread Safety:** safe.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[options, strutils]
import ids

type TraceContext* = object
  ## A parsed traceparent.
  ##
  ## **Description:** lowercase hexadecimal trace identifier (32), span
  ## identifier (16) and flags (2).
  ##
  ## **Business Justification:** Fields of logs and events.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  traceId*: string ## Trace identifier, 32 lowercase hex characters.
  spanId*: string ## Span identifier, 16 lowercase hex characters.
  flags*: string ## Trace flags, 2 lowercase hex characters.

proc isLowerHex(s: string, n: int): bool =
  ## Whether `s` has `n` lowercase hexadecimal characters.
  ##
  ## **Description:** Helper of `parseTraceparent`.
  ##
  ## **Business Justification:** The envelope requires lowercase.
  ##
  ## **Parameters:**
  ## - `s`: the text.
  ## - `n`: the expected length.
  ##
  ## **Returns:** `true` if well formed.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(n).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  s.len == n and allCharsInSet(s, {'0' .. '9', 'a' .. 'f'})

proc parseTraceparent*(value: string): Option[TraceContext] =
  ## Parses a traceparent value.
  ##
  ## **Description:** Version `00` only, lowercase, non-zero identifiers,
  ## as the envelope schema requires.
  ##
  ## **Business Justification:** The caller's trace is continued only if it
  ## is valid.
  ##
  ## **Parameters:**
  ## - `value`: the header or envelope field.
  ##
  ## **Returns:** the context, or `none` if invalid.
  ##
  ## **Errors:** `none` for any malformed value.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(1) (fixed length).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **See Also:** `renderTraceparent`.
  runnableExamples:
    import std/[options, strutils]
    let t = parseTraceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
    doAssert t.get.spanId == "00f067aa0ba902b7"
    doAssert parseTraceparent("00-" & '0'.repeat(32) & "-00f067aa0ba902b7-01").isNone
  let parts = value.split('-')
  if parts.len != 4 or parts[0] != "00":
    return none(TraceContext)
  let (t, s, f) = (parts[1], parts[2], parts[3])
  if not (isLowerHex(t, 32) and isLowerHex(s, 16) and isLowerHex(f, 2)):
    return none(TraceContext)
  if allCharsInSet(t, {'0'}) or allCharsInSet(s, {'0'}):
    return none(TraceContext)
  some(TraceContext(traceId: t, spanId: s, flags: f))

proc renderTraceparent*(ctx: TraceContext): string =
  ## Renders a context as a traceparent value.
  ##
  ## **Description:** `00-<traceId>-<spanId>-<flags>`.
  ##
  ## **Business Justification:** The `traceparent` of published events and
  ## of outgoing HTTP calls.
  ##
  ## **Parameters:**
  ## - `ctx`: the context.
  ##
  ## **Returns:** the traceparent text.
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
  ## **See Also:** `parseTraceparent`.
  runnableExamples:
    import std/strutils
    let ctx = TraceContext(traceId: 'a'.repeat(32), spanId: 'b'.repeat(16), flags: "01")
    doAssert renderTraceparent(ctx) == "00-" & 'a'.repeat(32) & "-" & 'b'.repeat(16) & "-01"
  "00-" & ctx.traceId & "-" & ctx.spanId & "-" & ctx.flags

proc nonZeroHex(bytes: int): string =
  ## Random hexadecimal text that is not all zeros.
  ##
  ## **Description:** Draws again in the (practically impossible) case of
  ## all zeros, which W3C forbids.
  ##
  ## **Business Justification:** Valid span and trace identifiers.
  ##
  ## **Parameters:**
  ## - `bytes`: number of random bytes.
  ##
  ## **Returns:** `2 * bytes` hexadecimal characters.
  ##
  ## **Errors:** `OSError` if the random source cannot be read.
  ##
  ## **Side Effects:** reads the random source.
  ##
  ## **Complexity:** O(bytes) expected.
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  result = randomHex(bytes)
  while allCharsInSet(result, {'0'}):
    result = randomHex(bytes)

proc childSpan*(parent: Option[TraceContext]): TraceContext =
  ## The context of a span that continues `parent`.
  ##
  ## **Description:** With a parent, keeps its trace and flags and draws a
  ## new span identifier; without one, starts a sampled trace.
  ##
  ## **Business Justification:** Continues the trace of the addition.
  ##
  ## **Parameters:**
  ## - `parent`: the caller's context, if valid.
  ##
  ## **Returns:** the context of the new span.
  ##
  ## **Errors:** `OSError` if the random source cannot be read.
  ##
  ## **Side Effects:** reads the random source.
  ##
  ## **Complexity:** O(1) expected.
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **See Also:** `parseTraceparent`.
  runnableExamples:
    import std/options
    let p = parseTraceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
    let c = childSpan(p)
    doAssert c.traceId == p.get.traceId and c.spanId != p.get.spanId
    doAssert childSpan(none(TraceContext)).flags == "01"
  if parent.isSome:
    TraceContext(traceId: parent.get.traceId, spanId: nonZeroHex(8),
        flags: parent.get.flags)
  else:
    TraceContext(traceId: nonZeroHex(16), spanId: nonZeroHex(8), flags: "01")
