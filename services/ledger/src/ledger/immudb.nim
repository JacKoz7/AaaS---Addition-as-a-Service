# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/immudb
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Minimal client of the immudb REST API v1 (login, SQL
#                  statements and queries, health).
# Related Docs:    ADR-0017, immudb REST API v1 (/api/docs/schema.swagger.json
#                  of the immudb web server), services/ledger/README.md

## Client of immudb's REST API v1.
##
## **Description:** immudb has no Nim client and its native protocol is
## gRPC, for which Nim has no mature library; the immudb web server
## exposes the same service as JSON over HTTP under `/api` (ADR-0017).
## The client logs in (`POST /api/login`, base64 user and password),
## selects the database (`GET /api/db/use/{name}`, which returns the token
## to use), and sends SQL with named parameters (`POST /api/db/sqlexec`,
## `POST /api/db/sqlquery`). Each request has a 2 s deadline and up to
## three attempts with jitter (CLAUDE.md 6.1); an expired or invalid token
## (gRPC code 16 or 13 with "token") triggers one new login. Requests share
## one keep-alive connection with `TCP_NODELAY` and are sent one at a time.
##
## **Business Justification:** The ledger's own database (CLAUDE.md 1,
## rule 4) is immudb, whose append-only storage keeps every version of
## every row.
##
## **Thread Safety:** not thread-safe; used from the event loop only.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[asyncdispatch, base64, httpclient, json, random, strutils]
import asyncmutex, nodelay

const
  requestTimeoutMs* = 2000
    ## Deadline of one request, in milliseconds (CLAUDE.md 6.1).
    ##
    ## **Description:** Covers connect, request and response.
    ##
    ## **Business Justification:** A hung database must not hang a task.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
  maxAttempts* = 3
    ## Attempts per request for transient failures (CLAUDE.md 6.1).
    ##
    ## **Description:** Timeouts and connection errors are transient.
    ##
    ## **Business Justification:** Survives a short database restart.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

type
  ImmuError* = object of CatchableError
    ## immudb answered with an error.
    ##
    ## **Description:** `code` is the gRPC status code of the answer, the
    ## message is immudb's.
    ##
    ## **Business Justification:** Callers distinguish duplicates
    ## (`isDuplicate`) from other errors.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    code*: int ## gRPC status code reported by immudb (2 = unknown, 13, 16).

  ImmuUnavailable* = object of CatchableError
    ## immudb could not be reached after `maxAttempts` attempts.
    ##
    ## **Description:** Timeouts, refused connections, closed sockets.
    ##
    ## **Business Justification:** Reported as the `database` health check
    ## and retried by the caller later.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

  SqlParam* = tuple[name: string, value: JsonNode]
    ## A named parameter (`@name` in the statement).
    ##
    ## **Description:** `value` is a JSON string, integer or boolean.
    ##
    ## **Business Justification:** Values are never spliced into SQL.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0

  ImmuClient* = ref object
    ## A logged-in client for one database.
    ##
    ## **Description:** Holds the credentials, the current token and the
    ## shared connection.
    ##
    ## **Business Justification:** One client per process.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    baseUrl: string ## immudb web server, e.g. `http://ledger-db:8080`.
    user: string ## immudb user.
    password: string ## Its password.
    database: string ## Database used after login.
    token: string ## Current session token, empty before login.
    http: AsyncHttpClient ## The shared connection, nil until needed.
    noDelay: NoDelayState ## Whether its socket has TCP_NODELAY.
    lock: AsyncMutex ## One request at a time on the connection.

proc isDuplicate*(e: ref ImmuError): bool =
  ## Whether the error is a unique key violation.
  ##
  ## **Description:** immudb reports it as `key already exists`.
  ##
  ## **Business Justification:** Repeated inserts are how idempotency is
  ## detected (processed events, one ledger entry per task).
  ##
  ## **Parameters:**
  ## - `e`: the error.
  ##
  ## **Returns:** `true` for a duplicate key.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(length of the message).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    let e = (ref ImmuError)(msg: "key already exists", code: 2)
    doAssert e.isDuplicate
  "key already exists" in e.msg

proc encodeParam*(p: SqlParam): JsonNode =
  ## The REST form of a parameter: `{"name", "value": {"s"|"n"|"b": ...}}`.
  ##
  ## **Description:** Integers travel as decimal strings (int64 in JSON
  ## of gRPC gateways).
  ##
  ## **Business Justification:** The wire format of `sqlexec`/`sqlquery`.
  ##
  ## **Parameters:**
  ## - `p`: the parameter.
  ##
  ## **Returns:** the JSON object.
  ##
  ## **Errors:** `ValueError` for another JSON kind.
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
    import std/json
    doAssert $encodeParam(("n", %5)) == """{"name":"n","value":{"n":"5"}}"""
  let v = case p.value.kind
    of JString: %*{"s": p.value.getStr}
    of JInt: %*{"n": $p.value.getBiggestInt}
    of JBool: %*{"b": p.value.getBool}
    else: raise newException(ValueError, "unsupported parameter kind " & $p.value.kind)
  %*{"name": p.name, "value": v}

proc decodeValue*(v: JsonNode): JsonNode =
  ## A column value of a query answer as a plain JSON value.
  ##
  ## **Description:** `{"s": x}` → string, `{"n": "5"}` → integer,
  ## `{"b": x}` → boolean, `{"null": ...}` or anything else → null.
  ##
  ## **Business Justification:** Callers work with plain values.
  ##
  ## **Parameters:**
  ## - `v`: one element of `values`.
  ##
  ## **Returns:** the value.
  ##
  ## **Errors:** `ValueError` if an integer is not decimal.
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
    import std/json
    doAssert decodeValue(%*{"n": "7"}).getInt == 7
    doAssert decodeValue(%*{"null": nil}).kind == JNull
  if v.kind != JObject:
    return newJNull()
  if v.hasKey("s"): return %v["s"].getStr
  if v.hasKey("n"):
    let n = v["n"]
    return (if n.kind == JString: %parseBiggestInt(n.getStr) else: %n.getBiggestInt)
  if v.hasKey("b"): return %v["b"].getBool
  newJNull()

proc newImmuClient*(baseUrl, user, password, database: string): ImmuClient =
  ## A client; the first request logs in.
  ##
  ## **Description:** No network access here.
  ##
  ## **Business Justification:** Startup does not depend on immudb being
  ## up yet; migrations retry until it is.
  ##
  ## **Parameters:**
  ## - `baseUrl`: the immudb web server without a trailing slash.
  ## - `user`, `password`: the credentials of the ledger user.
  ## - `database`: the database to use.
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
  ## **Example:** `let db = newImmuClient("http://ledger-db:8080", "ledger", password, "ledger")`.
  ##
  ## **See Also:** `exec`, `query`.
  ImmuClient(baseUrl: baseUrl, user: user, password: password,
      database: database, lock: newAsyncMutex())

proc send(c: ImmuClient, meth: HttpMethod, path, body: string,
    auth: bool): Future[JsonNode] {.async.} =
  ## One request with deadline and retries; the decoded JSON answer.
  ##
  ## **Description:** Requests share one keep-alive connection, one at a
  ## time (the client's lock); `TCP_NODELAY` is set on it after its first
  ## request (`ledger/nodelay`). A non-200 answer raises `ImmuError` with
  ## immudb's code and message; transient failures (timeouts, connection
  ## errors) close the connection and are retried up to `maxAttempts`
  ## times.
  ##
  ## **Business Justification:** The common transport of all calls.
  ##
  ## **Parameters:**
  ## - `c`: the client.
  ## - `meth`: the HTTP method.
  ## - `path`: the path below `/api`.
  ## - `body`: the JSON body, or empty.
  ## - `auth`: whether to send the token.
  ##
  ## **Returns:** the answer.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** 1..3 HTTP requests.
  ##
  ## **Complexity:** O(size of the answer).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  var lastError = ""
  for attemptNo in 1 .. maxAttempts:
    await c.lock.acquire()
    var healthy = false
    try:
      if c.http.isNil:
        c.http = newAsyncHttpClient()
        c.noDelay = NoDelayState()
      let headers = newHttpHeaders({"Content-Type": "application/json"})
      if auth:
        headers["Authorization"] = "Bearer " & c.token
      let fut = c.http.request(c.baseUrl & "/api" & path, meth, body, headers)
      if await withTimeout(fut, requestTimeoutMs):
        let resp = fut.read
        let bodyFut = resp.body
        if await withTimeout(bodyFut, requestTimeoutMs):
          healthy = true
          c.http.applyNoDelay(c.noDelay)
          let text = bodyFut.read
          let node = try: parseJson(text) except JsonParsingError, ValueError: newJNull()
          if resp.code == Http200 and node.kind == JObject:
            return node
          var err = newException(ImmuError, (if node.kind == JObject and
              node.hasKey("message"): node["message"].getStr else: "HTTP " &
              $resp.code.int & ": " & text))
          err.code = (if node.kind == JObject and node.hasKey("code"): node[
              "code"].getInt else: 0)
          raise err
        lastError = "no response body within " & $requestTimeoutMs & " ms"
      else:
        lastError = "no answer within " & $requestTimeoutMs & " ms"
    except ImmuError:
      raise
    except CatchableError as e:
      lastError = e.msg
    finally:
      # After a timeout or a connection error the state of the connection
      # is unknown: the next attempt opens a new one.
      if not healthy and not c.http.isNil:
        c.http.close()
        c.http = nil
      c.lock.release()
    if attemptNo < maxAttempts:
      await sleepAsync(rand(100 * attemptNo))
  raise newException(ImmuUnavailable, "immudb unavailable after " &
      $maxAttempts & " attempts: " & lastError)

proc login*(c: ImmuClient) {.async.} =
  ## Logs in and selects the database.
  ##
  ## **Description:** `POST /login` returns a token for the default
  ## database; `GET /db/use/{database}` returns the token for ours.
  ##
  ## **Business Justification:** Every SQL call needs the token.
  ##
  ## **Parameters:**
  ## - `c`: the client.
  ##
  ## **Returns:** nothing; the token is stored.
  ##
  ## **Errors:** `ImmuError` for wrong credentials or a missing
  ## database; `ImmuUnavailable`.
  ##
  ## **Side Effects:** two HTTP requests; replaces the token.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `await db.login()` (normally implicit in `exec` and `query`).
  let creds = $(%*{"user": encode(c.user), "password": encode(c.password)})
  let first = await c.send(HttpPost, "/login", creds, false)
  c.token = first["token"].getStr
  let used = await c.send(HttpGet, "/db/use/" & c.database, "", true)
  c.token = used["token"].getStr

proc isAuthError(e: ref ImmuError): bool =
  ## Whether the error asks for a new login.
  ##
  ## **Description:** gRPC codes 16 (unauthenticated) or 13 with a message
  ## about the token (immudb's answer to an invalid or expired token).
  ##
  ## **Business Justification:** Tokens expire after 24 hours.
  ##
  ## **Parameters:**
  ## - `e`: the error.
  ##
  ## **Returns:** `true` if a new login may help.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(length of the message).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  e.code == 16 or "token" in e.msg.toLowerAscii or "not logged" in e.msg

proc authorized(c: ImmuClient, path, body: string): Future[JsonNode] {.async.} =
  ## A POST with the token, logging in first or again when needed.
  ##
  ## **Description:** Logs in when there is no token; on an
  ## authentication error logs in once more and repeats the request.
  ##
  ## **Business Justification:** Callers never handle sessions.
  ##
  ## **Parameters:**
  ## - `c`: the client.
  ## - `path`: the path below `/api`.
  ## - `body`: the JSON body.
  ##
  ## **Returns:** the answer.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** 1..4 HTTP requests.
  ##
  ## **Complexity:** O(size of the answer).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  if c.token.len == 0:
    await c.login()
  try:
    return await c.send(HttpPost, path, body, true)
  except ImmuError as e:
    if not e.isAuthError:
      raise
  await c.login()
  return await c.send(HttpPost, path, body, true)

proc body(sql: string, params: openArray[SqlParam]): string =
  ## The JSON body of an SQL call.
  ##
  ## **Description:** `{"sql", "params"}`.
  ##
  ## **Business Justification:** Shared by `exec` and `query`.
  ##
  ## **Parameters:**
  ## - `sql`: the statement(s).
  ## - `params`: the named parameters.
  ##
  ## **Returns:** the body.
  ##
  ## **Errors:** `ValueError` for an unsupported parameter kind.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(size of the statement).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  var ps = newJArray()
  for p in params:
    ps.add(encodeParam(p))
  $(%*{"sql": sql, "params": ps})

proc rows(answer: JsonNode): seq[seq[JsonNode]] =
  ## The rows of a `sqlquery` answer as plain values.
  ##
  ## **Description:** Values are decoded with `decodeValue`; an answer
  ## without `rows` has none.
  ##
  ## **Business Justification:** Helper of `query`.
  ##
  ## **Parameters:**
  ## - `answer`: the decoded answer.
  ##
  ## **Returns:** the rows.
  ##
  ## **Errors:** `ValueError` for a malformed integer.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(size of the answer).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  if answer.hasKey("rows"):
    for row in answer["rows"]:
      var values: seq[JsonNode]
      for v in row["values"]:
        values.add(decodeValue(v))
      result.add(values)

proc queryText(c: ImmuClient, text: string): Future[seq[seq[JsonNode]]] {.async.} =
  ## Sends a serialized `sqlquery` body; the decoded rows.
  ##
  ## **Description:** The asynchronous part of `query` (an async proc
  ## cannot capture the `openArray` of parameters).
  ##
  ## **Business Justification:** Helper of `query`.
  ##
  ## **Parameters:**
  ## - `c`: the client.
  ## - `text`: the JSON body.
  ##
  ## **Returns:** the rows.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** HTTP requests.
  ##
  ## **Complexity:** O(size of the answer).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  return rows(await c.authorized("/db/sqlquery", text))

proc execText(c: ImmuClient, text: string) {.async.} =
  ## Sends a serialized `sqlexec` body.
  ##
  ## **Description:** The asynchronous part of `exec`.
  ##
  ## **Business Justification:** Helper of `exec`.
  ##
  ## **Parameters:**
  ## - `c`: the client.
  ## - `text`: the JSON body.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** HTTP requests; one immudb transaction.
  ##
  ## **Complexity:** O(size of the body).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  discard await c.authorized("/db/sqlexec", text)

proc exec*(c: ImmuClient, sql: string, params: openArray[SqlParam] = []): Future[void] =
  ## Executes statements; several statements form one transaction when
  ## wrapped in `BEGIN TRANSACTION; ... COMMIT;`.
  ##
  ## **Description:** A failed statement inside a transaction rolls back
  ## the whole transaction.
  ##
  ## **Business Justification:** Atomic writes (processed event and task,
  ## ledger entry and task status).
  ##
  ## **Parameters:**
  ## - `c`: the client.
  ## - `sql`: the statement text.
  ## - `params`: named parameters.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** `ImmuError` (use `isDuplicate` for unique keys),
  ## `ImmuUnavailable`. After a timeout the statement may have been
  ## applied: callers make writes idempotent with unique keys.
  ##
  ## **Side Effects:** one immudb transaction.
  ##
  ## **Complexity:** O(size of the statement) plus the database's work.
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `await db.exec("INSERT INTO t (k) VALUES (@k)", [("k", %"x")])`.
  c.execText(body(sql, params))

proc query*(c: ImmuClient, sql: string, params: openArray[SqlParam] = []): Future[
    seq[seq[JsonNode]]] =
  ## Runs a query; rows of plain values in the order of the select list.
  ##
  ## **Description:** Values are decoded with `decodeValue`.
  ##
  ## **Business Justification:** Reads of tasks and ledger entries.
  ##
  ## **Parameters:**
  ## - `c`: the client.
  ## - `sql`: the query.
  ## - `params`: named parameters.
  ##
  ## **Returns:** the rows (empty if none).
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** one HTTP request (more on retries or login).
  ##
  ## **Complexity:** O(size of the answer).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `let rows = await db.query("SELECT k FROM t")`.
  c.queryText(body(sql, params))

proc healthy*(c: ImmuClient): Future[bool] {.async.} =
  ## Whether the database answers a query.
  ##
  ## **Description:** Runs `SELECT COUNT(*) FROM schema_migrations` with
  ## the ledger's own session, which checks login, database selection and
  ## the SQL engine at once.
  ##
  ## **Business Justification:** The `database` check of `GET /health`.
  ##
  ## **Parameters:**
  ## - `c`: the client.
  ##
  ## **Returns:** `true` if the query succeeds.
  ##
  ## **Errors:** None (failures return `false`).
  ##
  ## **Side Effects:** one or more HTTP requests.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `if not await db.healthy(): echo "database failing"`.
  try:
    discard await c.query("SELECT COUNT(*) FROM schema_migrations")
    return true
  except CatchableError:
    return false
