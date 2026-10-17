# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          tests/test_unit
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Unit tests of the ledger that need no database and no
#                  broker: identifiers, hash chain, events against the
#                  contract examples, Peano loop, successor client against a
#                  local fake server, API routing, configuration, metrics.
# Related Docs:    services/ledger/README.md (Running and testing),
#                  contracts/events/, ADR-0013, ADR-0017

## Unit tests (`nim c -r tests/test_unit.nim`).
##
## **Description:** `CONTRACTS_DIR` points to `contracts/` (the valid and
## invalid examples are checked); `PRODUCED_DIR`, when set, receives every
## `aaas.ledger.appended.v1` event the tests build, which the `test` stage
## then validates against its JSON Schema with `scripts/validate-events.py`.
##
## **Business Justification:** The ledger's logic is verified on every
## build (CLAUDE.md 6.3).
##
## **Thread Safety:** single-threaded test program.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[asyncdispatch, asynchttpserver, json, options, os, strutils, tables, unittest]
import ledger/[api, asyncmutex, config, events, hashchain, ids, immudb, logging, metrics, peano,
    store, successor, trace]

let contracts = getEnv("CONTRACTS_DIR", "../../contracts")
  ## Root of the contracts.
  ##
  ## **Description:** `CONTRACTS_DIR`, default the repository layout.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0

proc examples(topic, kind: string): seq[string] =
  ## The example files of a topic, `valid` or `invalid`.
  ##
  ## **Description:** Sorted paths.
  ##
  ## **Business Justification:** Tests run against the contract examples.
  ##
  ## **Parameters:**
  ## - `topic`: the topic.
  ## - `kind`: `valid` or `invalid`.
  ##
  ## **Returns:** the paths.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** lists a directory.
  ##
  ## **Complexity:** O(files).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  for f in walkFiles(contracts / "events" / "examples" / topic / kind / "*.json"):
    result.add(f)

proc produced(event: string) =
  ## Writes a produced event to `PRODUCED_DIR` for schema validation.
  ##
  ## **Description:** Does nothing when the variable is unset.
  ##
  ## **Business Justification:** Produced events are checked against
  ## their schema.
  ##
  ## **Parameters:**
  ## - `event`: the event JSON.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** `IOError` if the file cannot be written.
  ##
  ## **Side Effects:** writes a file.
  ##
  ## **Complexity:** O(size of the event).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  let dir = getEnv("PRODUCED_DIR")
  if dir.len > 0:
    writeFile(dir / ("ledger-" & parseJson(event)["eventId"].getStr & ".json"), event)

suite "ids":
  test "timestamps have the fixed form":
    check formatTimestamp(0) == "1970-01-01T00:00:00.000Z"
    check formatTimestamp(1_792_152_002_530'i64) == "2026-10-16T12:00:02.530Z"
  test "UUIDv7 layout and ordering":
    let a = uuidV7()
    check isUuid(a)
    check a[14] == '7'
    check a[19] in {'8', '9', 'a', 'b'}
    check uuidV7FromParts(1, newSeq[byte](10)) < uuidV7FromParts(2, newSeq[byte](10))
  test "uppercase and malformed UUIDs are rejected":
    check not isUuid("018f3c2e-7b1a-7c3d-9f00-0000000000a")
    check not isUuid("018f3c2e_7b1a-7c3d-9f00-0000000000aa")

suite "hash chain":
  test "the valid contract examples reproduce their hashes":
    let files = examples("aaas.ledger.appended.v1", "valid")
    check files.len >= 2
    for f in files:
      let e = parseJson(readFile(f))
      let p = e["payload"]
      check entryHash(p["prevHash"].getStr, e["taskId"].getStr, p["a"].getBiggestInt,
          p["b"].getBiggestInt, p["result"].getBiggestInt, p["recordedAt"].getStr) ==
          p["hash"].getStr
  test "separators make the input unambiguous":
    check entryHash(genesisHash, "t", 1, 11, 12, "r") != entryHash(genesisHash, "t", 11, 1,
        12, "r")
  test "hash format":
    check isSha256Hex(entryHash(genesisHash, "t", 0, 0, 0, "r"))
    check not isSha256Hex(genesisHash[0 .. 62])

suite "trace":
  test "a child keeps the trace and the flags":
    let p = parseTraceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00")
    let c = childSpan(p)
    check c.traceId == "4bf92f3577b34da6a3ce929d0e0e4736"
    check c.flags == "00"
    check parseTraceparent(renderTraceparent(c)) == some(c)
  test "invalid values":
    for v in ["", "01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
        "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01",
        "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01"]:
      check parseTraceparent(v).isNone

suite "events":
  test "every valid addition.requested example decodes":
    let files = examples("aaas.addition.requested.v1", "valid")
    check files.len >= 3
    for f in files:
      let raw = parseJson(readFile(f))
      let e = decodeAdditionRequested($raw)
      check e.a == raw["payload"]["a"].getBiggestInt
      check e.b == raw["payload"]["b"].getBiggestInt
      check e.taskId == raw["taskId"].getStr
      check e.traceparent == raw["traceparent"].getStr
  test "invalid examples the ledger relies on are rejected":
    # The tolerant reader (ADR-0013) accepts unknown fields, a UUIDv4 and
    # other envelope details it does not use; these break what it uses.
    let rejected = ["envelope-payload-array", "envelope-task-id-null",
        "envelope-version-string", "envelope-wrong-type", "envelope-wrong-version",
        "payload-a-above-range", "payload-a-fraction", "payload-a-string",
        "payload-b-missing", "payload-b-negative"]
    var seen = 0
    for f in examples("aaas.addition.requested.v1", "invalid"):
      let name = f.extractFilename.changeFileExt("")
      if name in rejected:
        inc seen
        let event = $parseJson(readFile(f))["event"]
        expect DecodeError:
          discard decodeAdditionRequested(event)
    check seen == rejected.len
  test "an invalid traceparent is dropped, not fatal":
    let e = decodeAdditionRequested("""{"eventId":"018f3c2e-7b1a-7c3d-9f00-000000000001",
      "type":"aaas.addition.requested","version":1,"taskId":"018f3c2e-7b1a-7c3d-9f00-0000000000aa",
      "traceparent":"garbage","payload":{"a":1,"b":2}}""")
    check e.traceparent == ""
  test "not JSON":
    expect DecodeError:
      discard decodeAdditionRequested("{")
  test "ledger.appended matches the contract example and is produced":
    let ex = parseJson(readFile(examples("aaas.ledger.appended.v1", "valid")[0]))
    let p = ex["payload"]
    let entry = LedgerEntry(sequence: p["sequence"].getBiggestInt, taskId: ex["taskId"].getStr,
        a: p["a"].getBiggestInt, b: p["b"].getBiggestInt, sum: p["result"].getBiggestInt,
        recordedAt: p["recordedAt"].getStr, prevHash: p["prevHash"].getStr, hash: p[
        "hash"].getStr)
    let span = parseTraceparent(ex["traceparent"].getStr).get
    let built = parseJson(ledgerAppended(ex["eventId"].getStr, ex["occurredAt"].getStr, entry, span))
    check built == ex
    # A fresh event as the service builds it.
    let fresh = ledgerAppended(uuidV7(), formatTimestamp(nowMillis()), entry, childSpan(some(span)))
    produced(fresh)
    check parseJson(fresh)["payload"]["hash"].getStr == entry.hash

suite "peano":
  proc fakeNext(calls: ref int): NextProc =
    ## A successor that counts its calls.
    ##
    ## **Description:** Answers `n + 1`.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    result = proc(n: int64): Future[int64] {.async.} =
      inc calls[]
      return n + 1
  test "a + b by b calls":
    let calls = new int
    var saves: seq[CountState]
    let s = waitFor countUp(CountState(done: 0, current: 99_999), 2_500, fakeNext(calls), 1000,
        proc(st: CountState) {.async.} = saves.add(st),
        proc(st: CountState) = discard, proc(): bool = false)
    check s.current == 102_499
    check calls[] == 2_500
    check saves == @[CountState(done: 1000, current: 100_999), CountState(done: 2000,
        current: 101_999)]
  test "b = 0 makes no call":
    let calls = new int
    let s = waitFor countUp(CountState(done: 0, current: 7), 0, fakeNext(calls), 1000,
        proc(st: CountState) {.async.} = discard, proc(st: CountState) = discard,
        proc(): bool = false)
    check s.current == 7 and calls[] == 0
  test "resume from a checkpoint":
    let calls = new int
    let s = waitFor countUp(CountState(done: 3, current: 13), 5, fakeNext(calls), 1000,
        proc(st: CountState) {.async.} = discard, proc(st: CountState) = discard,
        proc(): bool = false)
    check s == CountState(done: 5, current: 15)
    check calls[] == 2
  test "stop writes a checkpoint of the reached state":
    let calls = new int
    var saved: seq[CountState]
    let s = waitFor countUp(CountState(done: 0, current: 0), 10, fakeNext(calls), 1000,
        proc(st: CountState) {.async.} = saved.add(st), proc(st: CountState) = discard,
        proc(): bool = calls[] >= 4)
    check s == CountState(done: 4, current: 4)
    check saved == @[s]

suite "successor client":
  proc fakeSuccessor(port: Port, answers: seq[(int, string)], seen: ref seq[string]) {.async.} =
    ## Serves `answers` in order on `port`, recording the bodies.
    ##
    ## **Description:** One answer per request.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    let server = newAsyncHttpServer()
    server.listen(port, "127.0.0.1")
    var i = 0
    proc cb(req: Request) {.async, gcsafe.} =
      {.cast(gcsafe).}:
        seen[].add(req.body & " tp=" & req.headers.getOrDefault("traceparent"))
        let (code, body) = answers[min(i, answers.len - 1)]
        inc i
        await req.respond(HttpCode(code), body, newHttpHeaders({
            "Content-Type": "application/json"}))
    proc acceptLoop() {.async.} =
      ## Accepts connections until the server is closed.
      ##
      ## **Description:** `acceptRequest` returns once a connection is
      ## accepted, before its requests are served.
      ##
      ## **Owner:** Transaction Integrity Office (TIO).
      ##
      ## **Since:** ledger 0.1.0
      while true:
        await server.acceptRequest(cb)
    # The pending accept of the closed server never completes; the loop
    # future is dropped on purpose.
    discard acceptLoop()
    while i < answers.len:
      await sleepAsync(10)
    server.close()

  test "retries a 503 and returns the answer":
    let seen = new seq[string]
    let srv = fakeSuccessor(Port(18_081), @[(503, "{}"), (200, """{"n":200}""")], seen)
    let r = newRegistry()
    r.register("ledger_successor_calls_total", "x", mkCounter, "outcome")
    let c = newSuccessorClient("http://127.0.0.1:18081", r, proc(): bool = false)
    check waitFor(c.next(199, "t", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")) == 200
    waitFor srv
    c.close()
    check seen[].len == 2
    check seen[0].startsWith("""{"n":199,"taskId":"t"}""")
    check seen[0].endsWith("tp=00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
    check "ledger_successor_calls_total{outcome=\"unavailable\"} 1" in r.render()
    check "ledger_successor_calls_total{outcome=\"ok\"} 1" in r.render()
  test "a 422 is permanent":
    let seen = new seq[string]
    let srv = fakeSuccessor(Port(18_082), @[(422, """{"detail":"no"}""")], seen)
    let c = newSuccessorClient("http://127.0.0.1:18082", newRegistry(), proc(): bool = false)
    expect SuccessorRejected:
      discard waitFor c.next(199_998, "t", "")
    waitFor srv
    c.close()
  test "stopping interrupts the retries":
    let c = newSuccessorClient("http://127.0.0.1:1", newRegistry(), proc(): bool = true)
    expect Interrupted:
      discard waitFor c.next(1, "t", "")
    c.close()
  test "backoff grows and is capped":
    check backoffMs(1) == 100
    check backoffMs(2) == 200
    check backoffMs(7) == 5000

suite "api":
  proc deps(view: Option[JsonNode], fail = false): ApiDeps =
    ## Fake dependencies answering `view`.
    ##
    ## **Description:** `fail` makes the lookup raise.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    ApiDeps(lookupTask: proc(id: string): Future[Option[JsonNode]] {.async.} =
      if fail:
        raise newException(ImmuUnavailable, "down")
      return view,
      health: proc(): Health = Health(checks: @[("database", true), ("broker", true)]),
      metrics: proc(): string = "ledger_up 1\n")
  const id = "018f3c2e-7b1a-7c3d-9f00-0000000000aa"
  test "task view":
    let v = %*{"taskId": id, "status": "RECORDED", "a": 3, "b": 2, "progress": {"done": 2,
        "total": 2}, "result": 5}
    let r = waitFor route(deps(some(v)), "GET", "/api/v1/tasks/" & id)
    check r.code == 200
    check parseJson(r.body) == v
  test "errors are problems":
    check (waitFor route(deps(none(JsonNode)), "GET", "/api/v1/tasks/" & id)).code == 404
    check (waitFor route(deps(none(JsonNode)), "GET", "/api/v1/tasks/NOT-A-UUID")).code == 400
    check (waitFor route(deps(none(JsonNode), true), "GET", "/api/v1/tasks/" & id)).code == 503
    check (waitFor route(deps(none(JsonNode)), "POST", "/api/v1/tasks/" & id)).code == 405
    check (waitFor route(deps(none(JsonNode)), "GET", "/api/v1/tasks/" & id & "/timer")).code == 404
    let p = waitFor route(deps(none(JsonNode)), "GET", "/nope")
    check p.contentType == "application/problem+json"
    check parseJson(p.body)["status"].getInt == 404
  test "health and metrics":
    let h = waitFor route(deps(none(JsonNode)), "GET", "/health?x=1")
    check h.code == 200
    check parseJson(h.body) == %*{"status": "ok", "checks": {"database": "ok", "broker": "ok"}}
    check (waitFor route(deps(none(JsonNode)), "GET", "/metrics")).body == "ledger_up 1\n"

suite "config":
  proc lookupOf(t: Table[string, string]): Lookup =
    ## A lookup reading `t`.
    ##
    ## **Description:** Missing keys are unset.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    result = proc(n: string): Option[string] =
      if n in t: some(t[n]) else: none(string)
  test "defaults":
    let c = loadConfig(lookupOf({"LEDGER_DB_PASSWORD": "x"}.toTable))
    check c.dbUrl == "http://ledger-db:8080"
    check c.consumerGroup == "ledger"
    check c.kafkaLogLevel == 4
    check c.logLevel == lvInfo
  test "errors":
    for t in [initTable[string, string](), {"LEDGER_DB_PASSWORD": "x",
        "AAAS_BOOTSTRAP": "platform"}.toTable, {"LEDGER_DB_PASSWORD": "x",
        "AAAS_HTTP_PORT": "0"}.toTable, {"LEDGER_DB_PASSWORD": "x",
        "AAAS_LOG_LEVEL": "loud"}.toTable, {"LEDGER_DB_PASSWORD": "x",
        "AAAS_CHECKPOINT_EVERY": "0"}.toTable]:
      expect ConfigError:
        discard loadConfig(lookupOf(t))
  test "trailing slashes are removed":
    let c = loadConfig(lookupOf({"LEDGER_DB_PASSWORD": "x",
        "AAAS_SUCCESSOR_URL": "http://s:1/"}.toTable))
    check c.successorUrl == "http://s:1"

suite "logging":
  test "fields in order, extra fields last":
    let tc = parseTraceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
    let line = renderLine("t", "ledger", lvWarn, "id", tc, "m", [("k", %1)])
    check line == """{"ts":"t","level":"warn","service":"ledger","msg":"m","taskId":"id","traceId":"4bf92f3577b34da6a3ce929d0e0e4736","spanId":"00f067aa0ba902b7","k":1}"""

suite "metrics":
  test "labelled counters and escaping":
    let r = newRegistry()
    r.register("ledger_x_total", "X.", mkCounter, "outcome")
    r.add("ledger_x_total", 2, "a\"b")
    r.add("ledger_unknown_total")
    check r.render() == "# HELP ledger_x_total X.\n# TYPE ledger_x_total counter\nledger_x_total{outcome=\"a\\\"b\"} 2\n"

suite "immudb encoding":
  test "parameters":
    check $encodeParam(("b", %true)) == """{"name":"b","value":{"b":true}}"""
    expect ValueError:
      discard encodeParam(("x", newJNull()))
  test "values":
    check decodeValue(%*{"s": "x"}).getStr == "x"
    check decodeValue(%*{"b": false}).getBool == false
    check decodeValue(%*{"n": "123456789012"}).getBiggestInt == 123456789012'i64

suite "store helpers":
  test "comment lines are removed":
    check stripComments("-- a\n  -- b\nSELECT 1;\n") == "SELECT 1;\n"

suite "async mutex":
  test "waiters are served in order":
    let m = newAsyncMutex()
    var order: seq[int]
    proc worker(i: int) {.async.} =
      await m.acquire()
      order.add(i)
      await sleepAsync(5)
      m.release()
    waitFor all([worker(1), worker(2), worker(3)])
    check order == @[1, 2, 3]
