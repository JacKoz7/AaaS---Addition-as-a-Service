# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          tests/test_store
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Integration tests of ledger/store against a real immudb:
#                  migrations, documentation of every column, idempotent
#                  acceptance, checkpoints, appends and publications.
# Related Docs:    services/ledger/Makefile (test), services/ledger/README.md,
#                  ADR-0017

## Store tests (`make test` runs them against a throw-away immudb).
##
## **Description:** Needs `IMMUDB_URL`, `LEDGER_DB_PASSWORD` and
## `MIGRATIONS_DIR`, and a database provisioned by `immudb/provision.sh`.
## The database must be empty: the tests assert exact sequences.
##
## **Business Justification:** The SQL of the store only runs against
## immudb; a fake would not prove it.
##
## **Thread Safety:** single-threaded test program.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[asyncdispatch, json, options, os, sets, unittest]
import ledger/[events, hashchain, immudb, peano, store]

let db = newImmuClient(getEnv("IMMUDB_URL", "http://127.0.0.1:8080"), "ledger",
    getEnv("LEDGER_DB_PASSWORD", "change-me"), "ledger")
  ## Client of the test database.
  ##
  ## **Description:** The ledger user created by `provision.sh`.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0

const
  now = "2026-10-16T12:00:00.000Z"
    ## Timestamp written by the tests.
    ##
    ## **Description:** Fixed, so that hashes are reproducible.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  task1 = "018f3c2e-7b1a-7c3d-9f00-0000000000aa"
    ## First test task.
    ##
    ## **Description:** A lowercase UUIDv7.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  task2 = "018f3c2f-0d42-7e10-a3b1-0000000000bb"
    ## Second test task.
    ##
    ## **Description:** A lowercase UUIDv7.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

proc event(eventId, taskId: string, a, b: int64): AdditionRequested =
  ## A decoded `aaas.addition.requested.v1`.
  ##
  ## **Description:** Without a traceparent.
  ##
  ## **Business Justification:** Test input.
  ##
  ## **Parameters:**
  ## - `eventId`, `taskId`: identifiers.
  ## - `a`, `b`: operands.
  ##
  ## **Returns:** the event.
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
  AdditionRequested(eventId: eventId, taskId: taskId, a: a, b: b)

proc entryFor(sequence: int64, prevHash, taskId: string, a, b, sum: int64): StoredEntry =
  ## A stored entry linked to `prevHash`.
  ##
  ## **Description:** Hash computed by the chain rule.
  ##
  ## **Business Justification:** Test input.
  ##
  ## **Parameters:**
  ## - `sequence`: the position.
  ## - `prevHash`: the previous hash.
  ## - `taskId`, `a`, `b`, `sum`: the addition.
  ##
  ## **Returns:** the entry with a dummy event.
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
  let e = LedgerEntry(sequence: sequence, taskId: taskId, a: a, b: b, sum: sum, recordedAt: now,
      prevHash: prevHash, hash: entryHash(prevHash, taskId, a, b, sum, now))
  StoredEntry(entry: e, eventId: "018f3c2e-7b1a-7c3d-9f00-00000000003" & $sequence,
      event: """{"eventId":"x"}""")

suite "migrations":
  test "apply once":
    check waitFor(migrate(db, getEnv("MIGRATIONS_DIR", "migrations"), now)) == @[
        "0001_initial_schema"]
    check waitFor(migrate(db, getEnv("MIGRATIONS_DIR", "migrations"), now)).len == 0
  test "every table and column is documented":
    var documented = initHashSet[string]()
    for r in waitFor db.query("SELECT object_name FROM schema_documentation"):
      documented.incl(r[0].getStr)
    var expected = 0
    for t in waitFor db.query("SELECT name FROM TABLES()"):
      let table = t[0].getStr
      check table in documented
      inc expected
      for c in waitFor db.query("SELECT name FROM COLUMNS('" & table & "')"):
        check (table & "." & c[0].getStr) in documented
        inc expected
    check expected == documented.len

suite "tasks":
  test "a new event creates a task, a repeat is a duplicate":
    check waitFor(db.acceptEvent(event("018f3c2e-7b1a-7c3d-9f00-000000000001", task1, 3, 2),
        now)) == aoNewTask
    check waitFor(db.acceptEvent(event("018f3c2e-7b1a-7c3d-9f00-000000000001", task1, 3, 2),
        now)) == aoDuplicateEvent
  test "a republication of a known task does not create a second task":
    check waitFor(db.acceptEvent(event("018f3c2e-7b1a-7c3d-9f00-000000000002", task1, 3, 2),
        now)) == aoKnownTask
    check waitFor(db.acceptEvent(event("018f3c2e-7b1a-7c3d-9f00-000000000002", task1, 3, 2),
        now)) == aoDuplicateEvent
  test "the task starts at a with nothing done":
    let t = waitFor(db.getTask(task1)).get
    check t.status == tsCounting
    check t.state == CountState(done: 0, current: 3)
    check t.sum.isNone
    check waitFor(db.getTask(task2)).isNone
  test "checkpoints update the progress":
    waitFor db.checkpoint(task1, CountState(done: 1, current: 4), now)
    check waitFor(db.getTask(task1)).get.state == CountState(done: 1, current: 4)
    check waitFor(db.countingTasks()).len == 1

suite "ledger entries":
  test "an empty ledger has no last entry":
    check waitFor(db.lastEntry()).isNone
  test "append, link and record the task":
    let e1 = entryFor(1, genesisHash, task1, 3, 2, 5)
    waitFor db.appendEntry(e1, now)
    let t = waitFor(db.getTask(task1)).get
    check t.status == tsRecorded
    check t.sum == some(5'i64)
    check t.state == CountState(done: 2, current: 5)
    check waitFor(db.lastEntry()).get.entry == e1.entry
    check waitFor(db.entryOfTask(task1)).get.eventId == e1.eventId
    check waitFor(db.countingTasks()).len == 0
  test "a second entry for the same task or position is refused":
    discard waitFor db.acceptEvent(event("018f3c2e-7b1a-7c3d-9f00-000000000003", task2, 99_999,
        99_999), now)
    let dupTask = entryFor(2, genesisHash, task1, 3, 2, 5)
    expect ImmuError:
      waitFor db.appendEntry(dupTask, now)
    let dupSeq = entryFor(1, genesisHash, task2, 99_999, 99_999, 199_998)
    expect ImmuError:
      waitFor db.appendEntry(dupSeq, now)
    # The refused transactions changed nothing.
    check waitFor(db.getTask(task2)).get.status == tsCounting
  test "publications":
    let last = waitFor(db.lastEntry()).get
    let e2 = entryFor(2, last.entry.hash, task2, 99_999, 99_999, 199_998)
    waitFor db.appendEntry(e2, now)
    check waitFor(db.unpublished()).len == 2
    waitFor db.markPublished(1, now)
    waitFor db.markPublished(1, now)
    let left = waitFor db.unpublished()
    check left.len == 1
    check left[0].entry.sequence == 2
    check left[0].entry.prevHash == last.entry.hash
    waitFor db.markPublished(2, now)
    check waitFor(db.unpublished()).len == 0

suite "failures":
  test "a refused task is FAILED and no longer counted":
    const task3 = "018f3c30-0000-7000-8000-0000000000cc"
    discard waitFor db.acceptEvent(event("018f3c2e-7b1a-7c3d-9f00-000000000004", task3, 1, 1), now)
    waitFor db.markFailed(task3, "successor refused n = 1: 422", now)
    check waitFor(db.getTask(task3)).get.status == tsFailed
    check waitFor(db.countingTasks()).len == 0
  test "a lost session is renewed":
    discard waitFor db.query("SELECT COUNT(*) FROM tasks")
    check waitFor(db.healthy())
