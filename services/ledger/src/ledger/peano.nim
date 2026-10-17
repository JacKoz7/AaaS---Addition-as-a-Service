# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/peano
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         The Peano loop of phase 1: a + b as b successor calls,
#                  resumable from a checkpoint.
# Related Docs:    CLAUDE.md 1 (rule 5) and 3 (step 7), ADR-0017

## Addition by repeated successor calls.
##
## **Description:** `a + b = S(S(...S(a)))`, `b` times. The loop holds a
## `CountState` (calls done, current value), asks the successor for the
## next value, and reports progress after every call and a checkpoint every
## `checkpointEvery` calls, so that a restarted ledger resumes from the last
## checkpoint instead of from `a`. Only the loop counter uses native `+`
## (allowed for loop counters by CLAUDE.md 1, rule 5); every value of the
## sum comes from the successor.
##
## TEMPORARY(P3.3): the loop runs in the ledger until the saga-orchestrator
## runs it as Temporal activities (with continue-as-new every 1000
## iterations); the ledger then only records the voted result.
##
## **Business Justification:** The core value proposition: Peano-compliant
## addition (CLAUDE.md 1, rule 5).
##
## **Thread Safety:** not thread-safe; one loop per task on the event loop.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/asyncdispatch

type
  CountState* = object
    ## Progress of one addition.
    ##
    ## **Description:** `done` successor calls made so far and `current`,
    ## the value after them (`a` when `done = 0`).
    ##
    ## **Business Justification:** Persisted as the checkpoint of a task
    ## and shown as `progress.done` by `GET /api/v1/tasks/{taskId}`.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    done*: int64 ## Successor calls made, 0..b.
    current*: int64 ## Value after `done` calls.

  NextProc* = proc(n: int64): Future[int64] {.closure.}
    ## One successor call: returns `n + 1` as computed by the successor.
    ##
    ## **Description:** Retries are the callee's concern; a raised error
    ## ends the loop.
    ##
    ## **Business Justification:** Injected so that the loop is tested
    ## without the network.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

  CheckpointProc* = proc(state: CountState): Future[void] {.closure.}
    ## Persists a checkpoint.
    ##
    ## **Description:** Called every `checkpointEvery` calls and when the
    ## loop stops early.
    ##
    ## **Business Justification:** A restart resumes from here.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

  StepProc* = proc(state: CountState) {.closure.}
    ## Observes the state after each call (in-memory progress, metrics).
    ##
    ## **Description:** Must not block.
    ##
    ## **Business Justification:** Live progress between checkpoints.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

  StopProc* = proc(): bool {.closure.}
    ## Whether the loop must stop (graceful shutdown).
    ##
    ## **Description:** Checked before each call.
    ##
    ## **Business Justification:** Shutdown within 10 s (CLAUDE.md 6.1).
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

proc countUp*(start: CountState, b: int64, next: NextProc,
    checkpointEvery: int, onCheckpoint: CheckpointProc, onStep: StepProc,
    stopping: StopProc): Future[CountState] {.async.} =
  ## Runs the remaining `b - start.done` successor calls.
  ##
  ## **Description:** Returns when `done = b` (the sum is `current`) or
  ## when `stopping` turns true; in the second case a checkpoint of the
  ## state reached is written first. A state already at `b` returns
  ## immediately, without any call (this is how `b = 0` gives `a`).
  ##
  ## **Business Justification:** See the module documentation.
  ##
  ## **Parameters:**
  ## - `start`: the state to resume from, `done` in 0..b.
  ## - `b`: total number of calls, 0..99 999.
  ## - `next`: the successor call.
  ## - `checkpointEvery`: calls between checkpoints, at least 1.
  ## - `onCheckpoint`: persists a checkpoint.
  ## - `onStep`: observes each step.
  ## - `stopping`: requests an early stop.
  ##
  ## **Returns:** the final state.
  ##
  ## **Errors:** whatever `next` or `onCheckpoint` raises.
  ##
  ## **Side Effects:** those of the callbacks: `b - start.done` successor
  ## calls and up to `(b - start.done) / checkpointEvery + 1` checkpoints.
  ##
  ## **Complexity:** O(b) calls; O(1) memory.
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **See Also:** `ledger/successor.next`, CLAUDE.md 1 (rule 5).
  runnableExamples:
    import std/asyncdispatch
    let fakeSuccessor: NextProc = proc(n: int64): Future[int64] {.async.} =
      return n + 1
    let noCheckpoint: CheckpointProc = proc(s: CountState) {.async.} = discard
    let s = waitFor countUp(CountState(done: 0, current: 3), 2, fakeSuccessor,
      1000, noCheckpoint, proc(s: CountState) = discard, proc(): bool = false)
    doAssert s.current == 5 and s.done == 2
  var state = start
  while state.done < b:
    if stopping():
      await onCheckpoint(state)
      return state
    state.current = await next(state.current)
    inc state.done
    onStep(state)
    if state.done < b and state.done mod checkpointEvery == 0:
      await onCheckpoint(state)
  return state
