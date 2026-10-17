# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/successor
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         HTTP client of the successor service: one keep-alive
#                  connection per task, timeouts and retries.
# Related Docs:    services/successor/README.md, ADR-0016, ADR-0017,
#                  CLAUDE.md 6.1

## Client of `POST /v1/next` of the successor service.
##
## **Description:** Sends `{"n", "taskId"}` with the task's `traceparent`
## and reads `{"n": n + 1}`. Each attempt has a 2 s deadline (CLAUDE.md
## 6.1). A 503, a 5xx, a timeout or a connection error is transient and
## retried with exponential backoff and full jitter (100 ms doubling up to
## 5 s); repeating a call is safe because the successor answers a repeated
## `(taskId, n)` from its call log (ADR-0016). A 4xx answer is permanent.
##
## TEMPORARY(P3.6): transient failures are retried until the call succeeds
## or the service stops; from P3.6 the attempts are bounded and the task is
## sent to the DLQ. TEMPORARY(P2.1): HTTP/JSON until the gRPC `Next`
## method exists.
##
## **Business Justification:** The ledger counts by successor calls
## (`TEMPORARY(P3.3)`), up to 99 999 per addition, so the connection is
## reused (about 2 ms per call instead of a new connection each time).
##
## **Thread Safety:** not thread-safe; one client per task.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[asyncdispatch, httpclient, json, random, times]
import metrics, nodelay

const
  attemptTimeoutMs* = 2000
    ## Deadline of one attempt in milliseconds (CLAUDE.md 6.1).
    ##
    ## **Description:** Covers connect, request and response body.
    ##
    ## **Business Justification:** A hung successor must not hang the task.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  firstBackoffMs* = 100
    ## Upper bound of the first retry delay, in milliseconds.
    ##
    ## **Description:** Doubles per attempt up to `maxBackoffMs`.
    ##
    ## **Business Justification:** Fast recovery from a restart.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  maxBackoffMs* = 5000
    ## Largest retry delay, in milliseconds.
    ##
    ## **Description:** Caps the exponential backoff.
    ##
    ## **Business Justification:** A recovered successor is used within
    ## 5 s.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

type
  SuccessorRejected* = object of CatchableError
    ## The successor refused the call (a 4xx answer).
    ##
    ## **Description:** The message carries the status and the problem
    ## detail. Repeating the call cannot succeed.
    ##
    ## **Business Justification:** The task is marked `FAILED`.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

  Interrupted* = object of CatchableError
    ## The service is stopping; the call was abandoned.
    ##
    ## **Description:** Raised instead of waiting for the next retry.
    ##
    ## **Business Justification:** Graceful shutdown within 10 s.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

  SuccessorClient* = ref object
    ## A connection to the successor for one task.
    ##
    ## **Description:** Holds the HTTP client (recreated after a failed
    ## attempt, whose connection state is unknown).
    ##
    ## **Business Justification:** Keep-alive per task.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    baseUrl: string ## e.g. `http://successor:8080`.
    http: AsyncHttpClient ## The current connection.
    noDelay: NoDelayState ## Whether its socket has TCP_NODELAY.
    metrics: Registry ## Where calls are counted.
    stopping: proc(): bool {.closure.} ## Shutdown flag.

proc newSuccessorClient*(baseUrl: string, metrics: Registry,
    stopping: proc(): bool {.closure.}): SuccessorClient =
  ## A client for one task.
  ##
  ## **Description:** The connection is opened by the first call.
  ##
  ## **Business Justification:** See the module documentation.
  ##
  ## **Parameters:**
  ## - `baseUrl`: the successor base URL, without a trailing slash.
  ## - `metrics`: the registry with `ledger_successor_calls_total`.
  ## - `stopping`: true once the service stops.
  ##
  ## **Returns:** the client.
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
  ## **Example:** `let c = newSuccessorClient("http://successor:8080", metrics, proc(): bool = stopping)`.
  ##
  ## **See Also:** `next`, `close`.
  SuccessorClient(baseUrl: baseUrl, http: newAsyncHttpClient(),
      metrics: metrics, stopping: stopping)

proc close*(c: SuccessorClient) =
  ## Closes the connection.
  ##
  ## **Description:** Safe to call more than once.
  ##
  ## **Business Justification:** Releases the socket when a task ends.
  ##
  ## **Parameters:**
  ## - `c`: the client.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** closes the socket.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `c.close()` when the task ends.
  c.http.close()

proc backoffMs*(attempt: int): int =
  ## Upper bound of the delay before retry `attempt` (1-based).
  ##
  ## **Description:** `firstBackoffMs * 2^(attempt-1)`, capped at
  ## `maxBackoffMs`; the actual delay is uniform in `0..bound` (full
  ## jitter).
  ##
  ## **Business Justification:** Retries of many tasks spread out instead
  ## of arriving together.
  ##
  ## **Parameters:**
  ## - `attempt`: 1 for the first retry.
  ##
  ## **Returns:** the bound in milliseconds.
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
  runnableExamples:
    doAssert backoffMs(1) == 100
    doAssert backoffMs(3) == 400
    doAssert backoffMs(30) == 5000
  result = firstBackoffMs
  for _ in 2 .. attempt:
    result *= 2
    if result >= maxBackoffMs:
      return maxBackoffMs

proc attempt(c: SuccessorClient, body, traceparent: string): Future[
    (int, string)] {.async.} =
  ## One HTTP attempt: status code and body.
  ##
  ## **Description:** Raises on a connection error.
  ##
  ## **Business Justification:** Wrapped by `next` with a deadline.
  ##
  ## **Parameters:**
  ## - `c`: the client.
  ## - `body`: the JSON request.
  ## - `traceparent`: the header value.
  ##
  ## **Returns:** status code and response body.
  ##
  ## **Errors:** `OSError`, `ProtocolError`, `HttpRequestError` on
  ## connection problems.
  ##
  ## **Side Effects:** one HTTP request; `TCP_NODELAY` on a new connection
  ## (`ledger/nodelay`).
  ##
  ## **Complexity:** O(size of the response).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  let headers = newHttpHeaders({"Content-Type": "application/json",
      "Accept": "application/json", "traceparent": traceparent})
  let resp = await c.http.request(c.baseUrl & "/v1/next", HttpPost, body, headers)
  let text = await resp.body
  c.http.applyNoDelay(c.noDelay)
  return (resp.code.int, text)

proc next*(c: SuccessorClient, n: int64, taskId,
    traceparent: string): Future[int64] {.async.} =
  ## Asks the successor for `n + 1`.
  ##
  ## **Description:** See the module documentation for timeouts and
  ## retries. The value returned is the successor's answer; the ledger
  ## does not compute it (CLAUDE.md 1, rule 5).
  ##
  ## **Business Justification:** One Peano step of the addition.
  ##
  ## **Parameters:**
  ## - `c`: the client of the task.
  ## - `n`: the argument, 0..199 997.
  ## - `taskId`: the task (part of the successor's call log key).
  ## - `traceparent`: the task's span.
  ##
  ## **Returns:** the successor's `n`.
  ##
  ## **Errors:** `SuccessorRejected` for a 4xx answer or a 200 without an
  ## integer `n`; `Interrupted` if the service stops while retrying.
  ##
  ## **Side Effects:** one or more HTTP calls; counts each attempt in
  ## `ledger_successor_calls_total` by outcome.
  ##
  ## **Complexity:** O(1) per attempt.
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `let s = await client.next(199, taskId, tp)  # s == 200`.
  ##
  ## **See Also:** `ledger/peano.countUp`, services/successor/README.md.
  let body = $(%*{"n": n, "taskId": taskId})
  var tries = 0
  while true:
    var outcome = "error"
    var transient = true
    var detail = ""
    let started = epochTime()
    let fut = c.attempt(body, traceparent)
    try:
      if await withTimeout(fut, attemptTimeoutMs):
        let (code, text) = fut.read
        if code == 200:
          let node = parseJson(text)
          if node.kind == JObject and node.hasKey("n") and node["n"].kind == JInt:
            c.metrics.add("ledger_successor_calls_total", 1, "ok")
            c.metrics.add("ledger_successor_call_seconds_total", epochTime() - started)
            return node["n"].getBiggestInt
          outcome = "invalid"
          transient = false
          detail = "200 without an integer n"
        elif code >= 400 and code < 500:
          outcome = "rejected"
          transient = false
          detail = $code & ": " & text
        else:
          outcome = "unavailable"
          detail = $code
      else:
        outcome = "timeout"
        detail = "no answer within " & $attemptTimeoutMs & " ms"
    except JsonParsingError, ValueError:
      outcome = "invalid"
      transient = false
      detail = "200 with a body that is not JSON"
    except CatchableError as e:
      outcome = "error"
      detail = e.msg
    c.metrics.add("ledger_successor_calls_total", 1, outcome)
    if not transient:
      raise newException(SuccessorRejected, "successor refused n = " & $n &
          ": " & detail)
    # The connection state after a failed attempt is unknown: start over.
    c.http.close()
    c.http = newAsyncHttpClient()
    c.noDelay = NoDelayState()
    inc tries
    let deadline = epochTime() + rand(backoffMs(tries)).float / 1000
    while epochTime() < deadline:
      if c.stopping():
        raise newException(Interrupted, "stopping while retrying n = " & $n &
            " (" & detail & ")")
      await sleepAsync(50)
