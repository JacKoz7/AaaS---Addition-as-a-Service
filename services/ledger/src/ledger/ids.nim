# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/ids
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Identifiers and timestamps: UUIDv7, the lowercase UUID
#                  check and the fixed millisecond UTC timestamp form.
# Related Docs:    ADR-0013, RFC 9562, services/ledger/README.md

## Identifiers and timestamps of the ledger.
##
## **Description:** Event identifiers are lowercase UUIDv7 (RFC 9562) and
## timestamps are UTC with exactly three fractional digits and `Z`
## (ADR-0013), because the ledger hash covers `recordedAt` and must be
## reproducible in every language.
##
## **Business Justification:** Every event and every ledger entry carries
## these values; a single implementation keeps them uniform.
##
## **Thread Safety:** safe.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[strutils, sysrand, times]

proc nowMillis*(): int64 =
  ## Current wall-clock time in Unix milliseconds.
  ##
  ## **Description:** Reads the system clock (UTC).
  ##
  ## **Business Justification:** The source of `occurredAt`, `recordedAt`
  ## and the UUIDv7 timestamp.
  ##
  ## **Returns:** milliseconds since 1970-01-01T00:00:00Z.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** reads the clock.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **See Also:** `formatTimestamp`.
  runnableExamples:
    doAssert nowMillis() > 1_700_000_000_000'i64
  let t = getTime()
  t.toUnix * 1000 + int64(t.nanosecond div 1_000_000)

proc formatTimestamp*(millis: int64): string =
  ## Formats Unix milliseconds as `YYYY-MM-DDTHH:MM:SS.mmmZ`.
  ##
  ## **Description:** UTC, exactly three fractional digits, the form of the
  ## `timestamp` definition of the event envelope.
  ##
  ## **Business Justification:** The fixed form keeps the ledger hash over
  ## `recordedAt` reproducible (ADR-0013).
  ##
  ## **Parameters:**
  ## - `millis`: Unix milliseconds, not negative.
  ##
  ## **Returns:** the timestamp text (24 characters).
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
  ## **See Also:** `nowMillis`.
  runnableExamples:
    doAssert formatTimestamp(1_792_152_000_000'i64) == "2026-10-16T12:00:00.000Z"
    doAssert formatTimestamp(7'i64) == "1970-01-01T00:00:00.007Z"
  let t = initTime(millis div 1000, int((millis mod 1000) * 1_000_000))
  t.utc.format("yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'")

proc isUuid*(s: string): bool =
  ## Whether `s` is a lowercase UUID in the 8-4-4-4-12 form.
  ##
  ## **Description:** Checks the length, the hyphens and lowercase
  ## hexadecimal digits; the version is not checked, so that task
  ## identifiers of any UUID version are looked up.
  ##
  ## **Business Justification:** Task identifiers in URLs and events are
  ## lowercase UUIDs (ADR-0013); anything else is rejected early.
  ##
  ## **Parameters:**
  ## - `s`: the candidate text.
  ##
  ## **Returns:** `true` for a lowercase UUID.
  ##
  ## **Errors:** None.
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
  ## **See Also:** `uuidV7`.
  runnableExamples:
    doAssert isUuid("018f3c2e-7b1a-7c3d-9f00-0000000000aa")
    doAssert not isUuid("018F3C2E-7B1A-7C3D-9F00-0000000000AA")
    doAssert not isUuid("not-a-uuid")
  if s.len != 36:
    return false
  for i, c in s:
    if i in [8, 13, 18, 23]:
      if c != '-':
        return false
    elif c notin {'0' .. '9', 'a' .. 'f'}:
      return false
  true

proc uuidV7FromParts*(millis: int64, random: openArray[byte]): string =
  ## Builds a UUIDv7 from a timestamp and ten random bytes.
  ##
  ## **Description:** 48 bits of Unix milliseconds, the version nibble `7`,
  ## 12 random bits, the variant bits `10` and 62 random bits (RFC 9562,
  ## section 5.7), in lowercase.
  ##
  ## **Business Justification:** Separated from `uuidV7` so that the
  ## layout is tested with fixed inputs.
  ##
  ## **Parameters:**
  ## - `millis`: Unix milliseconds (only the low 48 bits are used).
  ## - `random`: at least ten bytes of randomness.
  ##
  ## **Returns:** the UUID text.
  ##
  ## **Errors:** `IndexDefect` if `random` has fewer than ten bytes.
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
  ## **See Also:** `uuidV7`.
  runnableExamples:
    let id = uuidV7FromParts(1_792_152_000_000'i64, [0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 1])
    doAssert id == "01a14495-5600-7000-8000-000000000001"
  var b: array[16, byte]
  for i in 0 .. 5:
    b[i] = byte((millis shr (8 * (5 - i))) and 0xff)
  for i in 0 .. 9:
    b[6 + i] = random[i]
  b[6] = (b[6] and 0x0f) or 0x70
  b[8] = (b[8] and 0x3f) or 0x80
  var hex = ""
  for x in b:
    hex.add(toHex(x).toLowerAscii)
  hex[0 .. 7] & "-" & hex[8 .. 11] & "-" & hex[12 .. 15] & "-" & hex[16 .. 19] &
    "-" & hex[20 .. 31]

proc uuidV7*(): string =
  ## A new UUIDv7 from the clock and the operating system's random source.
  ##
  ## **Description:** Time-ordered, so identifiers sort by creation time.
  ##
  ## **Business Justification:** `eventId` of every published event
  ## (ADR-0013).
  ##
  ## **Returns:** the UUID text.
  ##
  ## **Errors:** `OSError` if the random source cannot be read.
  ##
  ## **Side Effects:** reads the clock and the random source.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **See Also:** `uuidV7FromParts`.
  runnableExamples:
    doAssert isUuid(uuidV7())
    doAssert uuidV7()[14] == '7'
  uuidV7FromParts(nowMillis(), urandom(10))

proc randomHex*(bytes: int): string =
  ## `bytes` random bytes as lowercase hexadecimal text.
  ##
  ## **Description:** Two characters per byte.
  ##
  ## **Business Justification:** Span and trace identifiers.
  ##
  ## **Parameters:**
  ## - `bytes`: number of bytes, 1..64.
  ##
  ## **Returns:** the hexadecimal text.
  ##
  ## **Errors:** `OSError` if the random source cannot be read.
  ##
  ## **Side Effects:** reads the random source.
  ##
  ## **Complexity:** O(bytes).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **See Also:** `ledger/trace`.
  runnableExamples:
    doAssert randomHex(8).len == 16
  for x in urandom(bytes):
    result.add(toHex(x).toLowerAscii)
