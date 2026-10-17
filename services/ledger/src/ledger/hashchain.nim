# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/hashchain
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         The hash rule of the ledger chain: SHA-256 over the
#                  `|`-separated fields of an entry.
# Related Docs:    ADR-0013, CLAUDE.md 3 (step 10),
#                  contracts/events/aaas.ledger.appended.v1.schema.json

## The hash chain of the ledger.
##
## **Description:** `hash = sha256(UTF-8("prevHash|taskId|a|b|result|recordedAt"))`
## in lowercase hexadecimal; numbers in decimal without leading zeros;
## the first entry links to `genesisHash` (64 zeros). This is the rule of
## ADR-0013, the same rule `cloud-notary` verifies (P10.3).
##
## **Business Justification:** Any change to a recorded addition breaks
## every later link, which makes the ledger tamper-evident.
##
## **Thread Safety:** pure; safe.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/strutils
import checksums/sha2

const genesisHash* = repeat('0', 64)
  ## `prevHash` of the first entry (sequence 1): 64 zeros.
  ##
  ## **Description:** There is no previous entry to link to.
  ##
  ## **Business Justification:** The anchor of the chain (ADR-0013).
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0

proc hashInput*(prevHash, taskId: string, a, b, sum: int64,
    recordedAt: string): string =
  ## The text that is hashed for one entry.
  ##
  ## **Description:** The six fields joined by `|`, numbers in decimal
  ## without leading zeros.
  ##
  ## **Business Justification:** Plain concatenation would be ambiguous
  ## (`1|11` and `11|1`); the separator makes the input unique (ADR-0013).
  ##
  ## **Parameters:**
  ## - `prevHash`: hash of the previous entry, 64 lowercase hex characters.
  ## - `taskId`: the task, a lowercase UUID.
  ## - `a`, `b`: the operands, 0..99 999.
  ## - `sum`: the recorded result, 0..199 998.
  ## - `recordedAt`: the recording timestamp in the fixed form.
  ##
  ## **Returns:** the UTF-8 text.
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
  ## **See Also:** `entryHash`.
  runnableExamples:
    doAssert hashInput("ab", "t", 3, 2, 5, "r") == "ab|t|3|2|5|r"
  [prevHash, taskId, $a, $b, $sum, recordedAt].join("|")

proc entryHash*(prevHash, taskId: string, a, b, sum: int64,
    recordedAt: string): string =
  ## SHA-256 of `hashInput`, in lowercase hexadecimal.
  ##
  ## **Description:** The `hash` of a ledger entry.
  ##
  ## **Business Justification:** Links the entry to the previous one.
  ##
  ## **Parameters:** as `hashInput`.
  ##
  ## **Returns:** 64 lowercase hexadecimal characters.
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
  ## **Example:** the first entry of the contract examples
  ## (`first-entry.json`).
  ##
  ## **See Also:** `hashInput`, ADR-0013.
  runnableExamples:
    doAssert entryHash(genesisHash, "018f3c2e-7b1a-7c3d-9f00-0000000000aa",
        3, 2, 5, "2026-10-16T12:00:02.530Z") ==
      "a528ebcccf497b893dfb1a855b84fab4885b574b9459e1c8d15925e231325dd3"
  var ctx = initSha_256()
  ctx.update(hashInput(prevHash, taskId, a, b, sum, recordedAt))
  toLowerAscii($ctx.digest())

proc isSha256Hex*(s: string): bool =
  ## Whether `s` is 64 lowercase hexadecimal characters.
  ##
  ## **Description:** The `sha256` definition of the event envelope.
  ##
  ## **Business Justification:** Hashes read back from the database are
  ## checked before they are linked to.
  ##
  ## **Parameters:**
  ## - `s`: the candidate text.
  ##
  ## **Returns:** `true` if well formed.
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
  ## **See Also:** `entryHash`.
  runnableExamples:
    doAssert isSha256Hex(genesisHash)
    doAssert not isSha256Hex("ABC")
  s.len == 64 and allCharsInSet(s, {'0' .. '9', 'a' .. 'f'})
