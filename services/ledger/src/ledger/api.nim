# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/api
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         HTTP API of the ledger: task status, health and metrics,
#                  with RFC 9457 problem details for every error.
# Related Docs:    CLAUDE.md 4.1 and 6.1, services/ledger/docs/API.md,
#                  services/gateway/config/dynamic/routes.yml

## The HTTP API.
##
## **Description:** `route` maps a method and a path to a `Reply`, using
## the functions of `ApiDeps`; it does no I/O of its own, so it is tested
## without a server. `ledger/service` connects it to `std/asynchttpserver`.
##
## | Method | Path | Answer |
## | --- | --- | --- |
## | `GET` | `/api/v1/tasks/{taskId}` | `200 {taskId, status, a, b, progress: {done, total}, result?}`; 400, 404, 503 problems |
## | `GET` | `/health` | `200 {status, checks}`, 503 when a check fails |
## | `GET` | `/metrics` | Prometheus text format |
##
## TEMPORARY(P3.3): `GET /api/v1/tasks/{taskId}` is answered by the ledger
## until the saga-orchestrator owns task status (the gateway's `tasks`
## upstream).
##
## **Business Justification:** The display polls the task status every
## second (CLAUDE.md 3, step 12).
##
## **Thread Safety:** pure; safe.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[asyncdispatch, json, options, strutils]
import ids

type
  Reply* = object
    ## An HTTP answer.
    ##
    ## **Description:** Status code, content type and body.
    ##
    ## **Business Justification:** The result of `route`.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    code*: int ## HTTP status code.
    contentType*: string ## Content-Type header.
    body*: string ## Body.

  Health* = object
    ## The result of the health checks.
    ##
    ## **Description:** One entry per check, `ok` or `failing`.
    ##
    ## **Business Justification:** `GET /health` (CLAUDE.md 6.1).
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    checks*: seq[(string, bool)] ## Check name and whether it passes.

  TaskLookup* = proc(taskId: string): Future[Option[JsonNode]] {.closure.}
    ## The task view of `GET /api/v1/tasks/{taskId}`, if the task is known.
    ##
    ## **Description:** Raises when the database is unavailable.
    ##
    ## **Business Justification:** Injected by `ledger/service`.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

  ApiDeps* = object
    ## What `route` needs.
    ##
    ## **Description:** Task lookup, health and metrics.
    ##
    ## **Business Justification:** Testability without a server.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    lookupTask*: TaskLookup ## Task view.
    health*: proc(): Health {.closure.} ## Last health result.
    metrics*: proc(): string {.closure.} ## Metrics exposition.

proc problem*(code: int, title, detail: string): Reply =
  ## An RFC 9457 problem reply.
  ##
  ## **Description:** `type` is `about:blank`, so `title` is the HTTP
  ## reason phrase.
  ##
  ## **Business Justification:** Errors of the public API are always
  ## problem details (CLAUDE.md 4.1).
  ##
  ## **Parameters:**
  ## - `code`: the status code.
  ## - `title`: the reason phrase.
  ## - `detail`: the explanation for this occurrence.
  ##
  ## **Returns:** the reply.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(size of the detail).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    doAssert problem(404, "Not Found", "x").contentType == "application/problem+json"
  Reply(code: code, contentType: "application/problem+json",
      body: $(%*{"type": "about:blank", "title": title, "status": code,
      "detail": detail}))

proc healthReply*(h: Health): Reply =
  ## The reply of `GET /health`.
  ##
  ## **Description:** `{"status": "ok"|"failing", "checks": {...}}`, 200 if
  ## every check passes, 503 otherwise.
  ##
  ## **Business Justification:** The Compose health check (CLAUDE.md 6.1).
  ##
  ## **Parameters:**
  ## - `h`: the check results.
  ##
  ## **Returns:** the reply.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(number of checks).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    doAssert healthReply(Health(checks: @[("database", true), ("broker", false)])).code == 503
  var checks = newJObject()
  var ok = true
  for (name, passes) in h.checks:
    checks[name] = %(if passes: "ok" else: "failing")
    ok = ok and passes
  Reply(code: (if ok: 200 else: 503), contentType: "application/json",
      body: $(%*{"status": (if ok: "ok" else: "failing"), "checks": checks}))

proc route*(deps: ApiDeps, meth, path: string): Future[Reply] {.async.} =
  ## Answers one request.
  ##
  ## **Description:** See the module table. A query string is ignored. A
  ## task identifier must be a lowercase UUID (400 otherwise); an unknown
  ## task is 404, which is also the answer while the ledger has not
  ## consumed the task's event yet and, until P3.6, forever for an
  ## expression the parser rejected. A database failure is 503.
  ##
  ## **Business Justification:** See the module documentation.
  ##
  ## **Parameters:**
  ## - `deps`: the dependencies.
  ## - `meth`: the HTTP method.
  ## - `path`: the request path.
  ##
  ## **Returns:** the reply.
  ##
  ## **Errors:** None (failures become problem replies).
  ##
  ## **Side Effects:** those of `deps.lookupTask` (one database query).
  ##
  ## **Complexity:** O(1) plus the lookup.
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `await route(deps, "GET", "/api/v1/tasks/<id>")` answers
  ## `200 {"taskId", "status": "COUNTING", ...}`.
  ##
  ## **See Also:** `problem`, `healthReply`.
  let p = path.split('?', 1)[0]
  const prefix = "/api/v1/tasks/"
  let known = p in ["/health", "/metrics"] or (p.startsWith(prefix) and
      '/' notin p[prefix.len .. ^1] and p.len > prefix.len)
  if not known:
    return problem(404, "Not Found", "no resource at " & p)
  if meth != "GET":
    return problem(405, "Method Not Allowed", meth & " is not allowed on " & p)
  if p == "/health":
    return healthReply(deps.health())
  if p == "/metrics":
    return Reply(code: 200, contentType: "text/plain; version=0.0.4; charset=utf-8",
        body: deps.metrics())
  let taskId = p[prefix.len .. ^1]
  if not isUuid(taskId):
    return problem(400, "Bad Request", "taskId must be a lowercase UUID")
  var view: Option[JsonNode]
  try:
    view = await deps.lookupTask(taskId)
  except CatchableError as e:
    return problem(503, "Service Unavailable", "task status is unavailable: " & e.msg)
  if view.isNone:
    return problem(404, "Not Found", "unknown task " & taskId)
  return Reply(code: 200, contentType: "application/json", body: $view.get)
