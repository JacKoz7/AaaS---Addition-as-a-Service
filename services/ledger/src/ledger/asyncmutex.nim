# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/asyncmutex
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         A first-come first-served lock for async procs on one
#                  event loop.
# Related Docs:    services/ledger/README.md (Processing), ADR-0017

## Async mutual exclusion.
##
## **Description:** `std/asyncdispatch` has no lock; this one keeps the
## waiters in a queue and hands the lock to the oldest on `release`.
##
## **Business Justification:** One append to the hash chain at a time
## (`TEMPORARY(P3.5)`, until the etcd lock `ledger-append`), and one request
## at a time on the shared immudb connection.
##
## **Thread Safety:** not thread-safe; one event loop only.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[asyncdispatch, deques]

type
  AsyncMutex* = ref object
    ## A first-come first-served lock for async procs.
    ##
    ## **Description:** `acquire` completes when the lock is free;
    ## `release` hands it to the next waiter.
    ##
    ## **Business Justification:** Serializes appends to the chain and the
    ## requests on the shared immudb connection.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    locked: bool ## Whether held.
    waiters: Deque[Future[void]] ## Waiting acquirers, in order.


proc newAsyncMutex*(): AsyncMutex =
  ## A free lock.
  ##
  ## **Description:** See `AsyncMutex`.
  ##
  ## **Business Justification:** The append lock.
  ##
  ## **Returns:** the lock.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `let lock = newAsyncMutex()`; see `acquire`.
  AsyncMutex(waiters: initDeque[Future[void]]())

proc acquire*(m: AsyncMutex): Future[void] =
  ## Waits for the lock and takes it.
  ##
  ## **Description:** Completes at once when free.
  ##
  ## **Business Justification:** See `AsyncMutex`.
  ##
  ## **Parameters:**
  ## - `m`: the lock.
  ##
  ## **Returns:** a future completed when the lock is held.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    import std/asyncdispatch
    let m = newAsyncMutex()
    waitFor m.acquire()
    let second = m.acquire()
    doAssert not second.finished
    m.release()
    doAssert second.finished
  result = newFuture[void]("AsyncMutex.acquire")
  if m.locked:
    m.waiters.addLast(result)
  else:
    m.locked = true
    result.complete()

proc release*(m: AsyncMutex) =
  ## Releases the lock, or hands it to the next waiter.
  ##
  ## **Description:** The next waiter's future completes at once.
  ##
  ## **Business Justification:** See `AsyncMutex`.
  ##
  ## **Parameters:**
  ## - `m`: the lock, held by the caller.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** completes a future.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `await m.acquire(); try: work() finally: m.release()`.
  if m.waiters.len > 0:
    m.waiters.popFirst().complete()
  else:
    m.locked = false
