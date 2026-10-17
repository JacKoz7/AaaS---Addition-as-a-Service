# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Entry point of the ledger service: configuration, HTTP
#                  server, consume loop and graceful shutdown.
# Related Docs:    services/ledger/README.md, CLAUDE.md 6.1, ADR-0017

## The `ledger` executable.
##
## **Description:** Reads the configuration (`ledger/config`), starts the
## HTTP server on `AAAS_HTTP_PORT` at once (so that `/health` answers,
## failing, while the database is not ready), applies the migrations,
## connects to Kafka, republishes and resumes (`ledger/service.recover`)
## and consumes until `SIGTERM` or `SIGINT`. Shutdown stops consuming,
## lets every task checkpoint (at most 7 s), closes Kafka and exits 0
## within the 10 s of CLAUDE.md 6.1. A configuration error exits 2.
##
## **Business Justification:** Runs the ledger in its container.
##
## **Thread Safety:** single-threaded (one async event loop).
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[asyncdispatch, asynchttpserver, envvars, json, options, posix]
import ledger/[api, config, logging, service]

var stopRequested: bool
  ## Whether `SIGTERM` or `SIGINT` was received.
  ##
  ## **Description:** Set by `onSignal`, read by `watchSignals`; a plain
  ## flag is the only thing a signal handler may safely write.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0

proc onSignal(sig: cint) {.noconv.} =
  ## Signal handler of `SIGTERM` and `SIGINT`: requests shutdown.
  ##
  ## **Description:** Only sets a flag (async-signal-safe).
  ##
  ## **Business Justification:** Graceful shutdown (CLAUDE.md 6.1).
  ##
  ## **Parameters:**
  ## - `sig`: the signal number.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** sets `stopRequested`.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** async-signal-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  stopRequested = true

proc envLookup(name: string): Option[string] =
  ## Reads an environment variable.
  ##
  ## **Description:** The production `Lookup` of `loadConfig`.
  ##
  ## **Business Justification:** Configuration from the environment.
  ##
  ## **Parameters:**
  ## - `name`: the variable.
  ##
  ## **Returns:** its value, if set.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** reads the environment.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  if existsEnv(name): some(getEnv(name)) else: none(string)

proc serveHttp(s: Service, server: AsyncHttpServer) {.async.} =
  ## Accepts HTTP requests and answers them with `ledger/api.route`.
  ##
  ## **Description:** Runs until the server is closed.
  ##
  ## **Business Justification:** The HTTP API (CLAUDE.md 6.1).
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ## - `server`: the listening server.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None (a failed request is logged).
  ##
  ## **Side Effects:** network I/O.
  ##
  ## **Complexity:** O(1) per request plus the route.
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  let deps = s.apiDeps()
  proc handle(req: Request) {.async, gcsafe.} =
    # std/asynchttpserver requires a GC-safe callback; the process has no
    # Nim threads (config.nims), so the closures of `deps` are safe here.
    {.cast(gcsafe).}:
      let reply = await route(deps, $req.reqMethod, req.url.path)
      await req.respond(HttpCode(reply.code), reply.body,
          newHttpHeaders({"Content-Type": reply.contentType}))
  while not s.stopping:
    try:
      if server.shouldAcceptRequest():
        await server.acceptRequest(handle)
      else:
        await sleepAsync(100)
    except CatchableError as e:
      if not s.stopping:
        s.logger.log(lvWarn, "http request failed", extra = [("error", %e.msg)])

proc watchSignals(s: Service) {.async.} =
  ## Turns a received signal into `s.stopping`.
  ##
  ## **Description:** Polls the flag every 50 ms.
  ##
  ## **Business Justification:** Every loop observes `stopping`.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ##
  ## **Returns:** when shutdown is requested.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** sets `s.stopping`.
  ##
  ## **Complexity:** O(1) per round.
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  while not stopRequested:
    await sleepAsync(50)
  s.stopping = true
  s.logger.log(lvInfo, "shutdown requested")

proc main(): int =
  ## Runs the service; the process exit code.
  ##
  ## **Description:** See the module documentation.
  ##
  ## **Business Justification:** The executable.
  ##
  ## **Returns:** 0 after a graceful shutdown, 2 for a configuration error,
  ## 1 for a Kafka setup error.
  ##
  ## **Errors:** None (errors become the exit code).
  ##
  ## **Side Effects:** everything the service does.
  ##
  ## **Complexity:** the lifetime of the service.
  ##
  ## **Thread Safety:** single-threaded.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  var cfg: Config
  try:
    cfg = loadConfig(envLookup)
  except ConfigError as e:
    stderr.writeLine("ledger: configuration error: " & e.msg)
    return 2
  let logger = newLogger(cfg.service, cfg.logLevel)
  let s = newService(cfg, logger)
  signal(SIGTERM, onSignal)
  signal(SIGINT, onSignal)
  let server = newAsyncHttpServer()
  server.listen(Port(cfg.httpPort))
  logger.log(lvInfo, "started", extra = [("version", %version),
      ("port", %cfg.httpPort)])
  let signals = watchSignals(s)
  let http = serveHttp(s, server)
  let health = healthLoop(s)
  waitFor s.prepare()
  if not s.stopping:
    try:
      s.start()
    except CatchableError as e:
      logger.log(lvFatal, "kafka setup failed", extra = [("error", %e.msg)])
      return 1
    let serving = serveLoop(s)
    waitFor s.recover()
    waitFor s.consumeLoop()
    waitFor s.drain(7000)
    waitFor serving
  waitFor signals
  server.close()
  # The health and HTTP loops end on their own; a database check in progress
  # (up to 6 s) must not delay the exit.
  discard health
  discard http
  logger.log(lvInfo, "stopped")
  0

when isMainModule:
  quit(main())
