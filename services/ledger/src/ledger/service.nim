# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/service
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         The ledger use cases: accept additions, count them by
#                  successor calls, append the results to the hash chain and
#                  announce them; resume after a restart.
# Related Docs:    services/ledger/README.md (Processing), CLAUDE.md 3
#                  (steps 7 and 10), ADR-0013, ADR-0017

## The ledger service.
##
## **Description:**
##
## 1. **Accept.** Each consumed `aaas.addition.requested.v1` is decoded and
##    stored with its task (`ledger/store.acceptEvent`); only then is its
##    offset committed. A malformed event is logged and committed
##    (`TEMPORARY(P3.6)`: sent to the DLQ from P3.6).
## 2. **Count.** Every new task runs concurrently with the others: `b`
##    successor calls from `a` (`ledger/peano`, `TEMPORARY(P3.3)`), with a
##    checkpoint every `checkpointEvery` calls.
## 3. **Append.** Under the append lock (one append at a time, so the chain
##    has no forks: `TEMPORARY(P3.5)`, an in-process lock until the etcd
##    lock `ledger-append`), the entry is linked to the last one, hashed
##    (ADR-0013) and stored with its task status in one transaction.
## 4. **Announce.** Still under the lock, `aaas.ledger.appended.v1` is
##    published and, once acknowledged, recorded in `publications`.
##
## At startup, unpublished entries are published again and `COUNTING`
## tasks resume from their last checkpoint. Repeated successor calls are
## safe (the successor answers them from its call log), so a lost
## checkpoint costs time, never correctness.
##
## **Business Justification:** The record of every result (CLAUDE.md 3,
## step 10) and, until P3.3, the Peano computation itself.
##
## **Thread Safety:** not thread-safe; everything runs on one event loop.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[asyncdispatch, json, options, random, tables]
import api, asyncmutex, config, events, hashchain, ids, immudb, kafka, logging,
    metrics, peano, store, successor, trace

const version* = "0.1.0"
  ## Version of the ledger service (SemVer, `services/ledger/CHANGELOG`).
  ##
  ## **Description:** Exported as `ledger_build_info{version}`.
  ##
  ## **Business Justification:** Release traceability.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0

type
  LiveTask = object
    ## A task being counted by this process.
    ##
    ## **Description:** Fresher than the database between checkpoints.
    ##
    ## **Business Justification:** Live progress for the display.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    row: TaskRow ## The task as accepted or resumed.
    state: CountState ## Progress after the last successor call.
    status: TaskStatus ## `tsCounting` or `tsRecording`.

  Service* = ref object
    ## The running service.
    ##
    ## **Description:** Built by `newService`, run by `run`.
    ##
    ## **Business Justification:** One object holds the process state.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    cfg*: Config ## Configuration.
    logger*: Logger ## Log output.
    metrics*: Registry ## Metrics.
    db*: ImmuClient ## Database client.
    consumer: KafkaConsumer ## Consumer, after `start`.
    producer: KafkaProducer ## Producer, after `start`.
    live: Table[string, LiveTask] ## Tasks being counted.
    running: seq[Future[void]] ## Their futures.
    appendLock: AsyncMutex ## Serializes appends.
    stopping*: bool ## Shutdown requested.
    dbHealthy: bool ## Last database check.

proc nowText(): string =
  ## The current time in the fixed timestamp form.
  ##
  ## **Description:** `formatTimestamp(nowMillis())`.
  ##
  ## **Business Justification:** Timestamps of rows and events.
  ##
  ## **Returns:** the timestamp.
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
  formatTimestamp(nowMillis())

proc newService*(cfg: Config, logger: Logger): Service =
  ## The service with its metrics declared; nothing is started.
  ##
  ## **Description:** `start` connects to Kafka, `run` runs everything.
  ##
  ## **Business Justification:** See the module documentation.
  ##
  ## **Parameters:**
  ## - `cfg`: the configuration.
  ## - `logger`: the logger.
  ##
  ## **Returns:** the service.
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
  ## **Example:** `let s = newService(loadConfig(lookup), newLogger("ledger", lvInfo))`.
  let r = newRegistry()
  r.register("ledger_up", "Whether the ledger process is running.", mkGauge)
  r.register("ledger_build_info", "Version of the running ledger.", mkGauge, "version")
  r.register("ledger_events_consumed_total",
      "Consumed aaas.addition.requested.v1 messages by outcome.", mkCounter, "outcome")
  r.register("ledger_successor_calls_total",
      "Attempts of successor calls by outcome.", mkCounter, "outcome")
  r.register("ledger_successor_call_seconds_total",
      "Seconds spent in successful successor calls.", mkCounter)
  r.register("ledger_tasks_active", "Tasks being counted or recorded by this process.", mkGauge)
  r.register("ledger_tasks_finished_total", "Tasks that ended, by final status.",
      mkCounter, "status")
  r.register("ledger_entries_appended_total", "Entries appended to the hash chain.", mkCounter)
  r.register("ledger_publish_failures_total",
      "Failed publications of aaas.ledger.appended.v1 (each is retried).", mkCounter)
  r.register("ledger_database_failures_total",
      "Database operations that failed after their retries.", mkCounter)
  r.set("ledger_up", 1)
  r.set("ledger_build_info", 1, version)
  Service(cfg: cfg, logger: logger, metrics: r,
      db: newImmuClient(cfg.dbUrl, cfg.dbUser, cfg.dbPassword, cfg.dbName),
      appendLock: newAsyncMutex())

proc taskView*(s: Service, taskId: string): Future[Option[JsonNode]] {.async.} =
  ## The answer of `GET /api/v1/tasks/{taskId}`.
  ##
  ## **Description:** A task counted by this process is shown with its live
  ## progress; any other task from the database. `result` appears only for
  ## `RECORDED`.
  ##
  ## **Business Justification:** The display shows progress and result.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ## - `taskId`: the task.
  ##
  ## **Returns:** `{taskId, status, a, b, progress: {done, total}, result?}`,
  ## or `none` if unknown.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** at most one query.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `await s.taskView(id)` gives `some({"taskId": id, "status": "COUNTING", "a": 3, "b": 2, "progress": {"done": 1, "total": 2}})`.
  var row: TaskRow
  var state: CountState
  var status: TaskStatus
  if taskId in s.live:
    let t = s.live[taskId]
    (row, state, status) = (t.row, t.state, t.status)
  else:
    let found = await s.db.getTask(taskId)
    if found.isNone:
      return none(JsonNode)
    (row, state, status) = (found.get, found.get.state, found.get.status)
  let view = %*{"taskId": row.taskId, "status": $status, "a": row.a, "b": row.b,
      "progress": {"done": state.done, "total": row.b}}
  if status == tsRecorded and row.sum.isSome:
    view["result"] = %row.sum.get
  return some(view)

proc pause(s: Service, attempt: int) {.async.} =
  ## Waits before retrying a database or broker operation.
  ##
  ## **Description:** Full jitter up to `backoffMs(attempt)`; returns
  ## early when the service stops.
  ##
  ## **Business Justification:** Retries spread out.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ## - `attempt`: 1 for the first retry.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** sleeps.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  var left = rand(backoffMs(attempt))
  while left > 0 and not s.stopping:
    await sleepAsync(min(left, 50))
    left -= 50

proc publishEntry(s: Service, stored: StoredEntry) {.async.} =
  ## Publishes the event of an entry until acknowledged, then records it.
  ##
  ## **Description:** Retries until it succeeds or the service stops (the
  ## entry is then published at the next start).
  ##
  ## **Business Justification:** At-least-once announcement of every
  ## entry; consumers deduplicate by `eventId`.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ## - `stored`: the entry and its event.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** Kafka messages; one row in `publications`.
  ##
  ## **Complexity:** O(1) per attempt.
  ##
  ## **Thread Safety:** event loop only; call under the append lock.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  var attempt = 0
  while not s.stopping:
    try:
      await s.producer.publish(appendedTopic, stored.entry.taskId, stored.event)
      await s.db.markPublished(stored.entry.sequence, nowText())
      s.logger.log(lvInfo, "ledger entry published", stored.entry.taskId,
          extra = [("sequence", %stored.entry.sequence), ("eventId", %stored.eventId)])
      return
    except CatchableError as e:
      inc attempt
      s.metrics.add("ledger_publish_failures_total")
      s.logger.log(lvWarn, "publication failed, retrying", stored.entry.taskId,
          extra = [("sequence", %stored.entry.sequence), ("error", %e.msg),
          ("attempt", %attempt)])
      await s.pause(attempt)

proc appendResult(s: Service, row: TaskRow, sum: int64,
    span: TraceContext): Future[bool] {.async.} =
  ## Appends the result of a task to the chain and publishes it.
  ##
  ## **Description:** Under the append lock: if the task already has an
  ## entry (a repeated append after a timeout) that entry is used;
  ## otherwise the next entry is linked to the last one, hashed and stored
  ## with the task status. Database failures are retried until success or
  ## shutdown.
  ##
  ## **Business Justification:** CLAUDE.md 3, step 10.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ## - `row`: the task.
  ## - `sum`: the counted result.
  ## - `span`: the span of the task, parent of the event's span.
  ##
  ## **Returns:** `true` if appended (and published, unless stopping).
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** one ledger transaction; Kafka messages.
  ##
  ## **Complexity:** O(1) queries per attempt.
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  await s.appendLock.acquire()
  try:
    var attempt = 0
    while not s.stopping:
      try:
        var stored: StoredEntry
        let existing = await s.db.entryOfTask(row.taskId)
        if existing.isSome:
          stored = existing.get
        else:
          let last = await s.db.lastEntry()
          let recordedAt = nowText()
          var entry = LedgerEntry(taskId: row.taskId, a: row.a, b: row.b,
              sum: sum, recordedAt: recordedAt)
          if last.isSome:
            entry.sequence = last.get.entry.sequence + 1
            entry.prevHash = last.get.entry.hash
          else:
            entry.sequence = 1
            entry.prevHash = genesisHash
          entry.hash = entryHash(entry.prevHash, entry.taskId, entry.a,
              entry.b, entry.sum, entry.recordedAt)
          let eventId = uuidV7()
          stored = StoredEntry(entry: entry, eventId: eventId,
              event: ledgerAppended(eventId, recordedAt, entry, childSpan(some(span))))
          await s.db.appendEntry(stored, recordedAt)
          s.metrics.add("ledger_entries_appended_total")
          s.logger.log(lvInfo, "ledger entry appended", row.taskId, some(span),
              [("sequence", %entry.sequence), ("a", %entry.a), ("b", %entry.b),
              ("result", %entry.sum), ("hash", %entry.hash)])
        await s.publishEntry(stored)
        return true
      except CatchableError as e:
        inc attempt
        s.metrics.add("ledger_database_failures_total")
        s.logger.log(lvWarn, "append failed, retrying", row.taskId, some(span),
            [("error", %e.msg), ("attempt", %attempt)])
        await s.pause(attempt)
    return false
  finally:
    s.appendLock.release()

proc runTask(s: Service, row: TaskRow) {.async.} =
  ## Counts one task and records its result.
  ##
  ## **Description:** Resumes from `row.state`. Checkpoint failures are
  ## logged and do not stop the count (the next checkpoint or a restart
  ## from an older one recovers). A refused successor call marks the task
  ## `FAILED`. On shutdown the reached state is checkpointed.
  ##
  ## **Business Justification:** Steps 2 to 4 of the module documentation.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ## - `row`: the task, `COUNTING`.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None (every failure is handled here).
  ##
  ## **Side Effects:** `b - done` successor calls; checkpoints; one ledger
  ## entry; one event.
  ##
  ## **Complexity:** O(b) calls.
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  let taskId = row.taskId
  let span = childSpan(parseTraceparent(row.traceparent))
  let tp = renderTraceparent(span)
  let client = newSuccessorClient(s.cfg.successorUrl, s.metrics,
      proc(): bool = s.stopping)
  s.live[taskId] = LiveTask(row: row, state: row.state, status: tsCounting)
  s.metrics.set("ledger_tasks_active", float(s.live.len))
  s.logger.log(lvInfo, "counting started", taskId, some(span),
      [("a", %row.a), ("b", %row.b), ("done", %row.state.done)])
  let started = nowMillis()
  proc save(state: CountState) {.async.} =
    try:
      await s.db.checkpoint(taskId, state, nowText())
    except CatchableError as e:
      s.metrics.add("ledger_database_failures_total")
      s.logger.log(lvWarn, "checkpoint failed", taskId, some(span),
          [("done", %state.done), ("error", %e.msg)])
  try:
    let final = await countUp(row.state, row.b,
        proc(n: int64): Future[int64] = client.next(n, taskId, tp),
        s.cfg.checkpointEvery, save,
        proc(state: CountState) = s.live[taskId].state = state,
        proc(): bool = s.stopping)
    if final.done < row.b:
      s.logger.log(lvInfo, "counting paused for shutdown", taskId, some(span),
          [("done", %final.done)])
      return
    s.live[taskId].status = tsRecording
    s.logger.log(lvInfo, "counting finished", taskId, some(span),
        [("result", %final.current), ("calls", %(row.b - row.state.done)),
        ("ms", %(nowMillis() - started))])
    if await s.appendResult(row, final.current, span):
      s.metrics.add("ledger_tasks_finished_total", 1, $tsRecorded)
  except Interrupted:
    await save(s.live[taskId].state)
    s.logger.log(lvInfo, "counting paused for shutdown", taskId, some(span),
        [("done", %s.live[taskId].state.done)])
  except SuccessorRejected as e:
    s.logger.log(lvError, "successor refused a call; task failed", taskId,
        some(span), [("error", %e.msg)])
    try:
      await s.db.markFailed(taskId, e.msg, nowText())
      s.metrics.add("ledger_tasks_finished_total", 1, $tsFailed)
    except CatchableError as e2:
      s.logger.log(lvError, "could not mark the task failed", taskId,
          some(span), [("error", %e2.msg)])
  finally:
    client.close()
    s.live.del(taskId)
    s.metrics.set("ledger_tasks_active", float(s.live.len))

proc spawn(s: Service, row: TaskRow) =
  ## Starts `runTask` without waiting for it.
  ##
  ## **Description:** The future is kept so that shutdown can wait for it.
  ## A task already counted by this process is not started twice.
  ##
  ## **Business Justification:** Tasks run concurrently.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ## - `row`: the task.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** starts a task.
  ##
  ## **Complexity:** O(number of running tasks).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  if row.taskId in s.live:
    return
  var still: seq[Future[void]]
  for f in s.running:
    if not f.finished:
      still.add(f)
  still.add(s.runTask(row))
  s.running = still

proc handleMessage*(s: Service, msg: KafkaMessage): Future[bool] {.async.} =
  ## Processes one consumed message; `true` if its offset may be committed.
  ##
  ## **Description:** Decodes it (a malformed event is committed and
  ## counted as `rejected`), stores it, retrying database failures until
  ## success or shutdown (`false`: not committed, delivered again), and
  ## starts counting a new task.
  ##
  ## **Business Justification:** Step 1 of the module documentation.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ## - `msg`: the message.
  ##
  ## **Returns:** whether to commit.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** database writes; may start a task.
  ##
  ## **Complexity:** O(size of the message).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `if await s.handleMessage(msg): s.consumer.commit(msg)`.
  var ev: AdditionRequested
  try:
    ev = decodeAdditionRequested(msg.value)
  except DecodeError as e:
    # TEMPORARY(P3.6): a malformed event is logged and skipped until the
    # dead-letter service exists; it is sent to aaas.dlq.v1 from P3.6.
    s.metrics.add("ledger_events_consumed_total", 1, "rejected")
    s.logger.log(lvWarn, "event rejected", msg.key, extra = [("error", %e.msg),
        ("partition", %msg.partition), ("offset", %msg.offset)])
    return true
  let tctx = parseTraceparent(ev.traceparent)
  var attempt = 0
  while not s.stopping:
    try:
      let outcome = await s.db.acceptEvent(ev, nowText())
      s.metrics.add("ledger_events_consumed_total", 1, $outcome)
      s.logger.log(lvInfo, "event consumed", ev.taskId, tctx,
          [("eventId", %ev.eventId), ("outcome", %($outcome)), ("a", %ev.a), ("b", %ev.b)])
      if outcome == aoNewTask:
        s.spawn(TaskRow(taskId: ev.taskId, a: ev.a, b: ev.b, status: tsCounting,
            state: CountState(done: 0, current: ev.a), traceparent: ev.traceparent))
      return true
    except CatchableError as e:
      inc attempt
      s.metrics.add("ledger_database_failures_total")
      s.logger.log(lvWarn, "storing the event failed, retrying", ev.taskId,
          tctx, [("error", %e.msg), ("attempt", %attempt)])
      await s.pause(attempt)
  return false

proc health*(s: Service): Health =
  ## The last health results.
  ##
  ## **Description:** `database` from the last periodic check, `broker`
  ## from the last librdkafka statistics of both handles.
  ##
  ## **Business Justification:** `GET /health`.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ##
  ## **Returns:** the checks.
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
  ## **Example:** `healthReply(s.health())`.
  let broker = s.consumer != nil and s.producer != nil and
      s.consumer.connected and s.producer.connected
  Health(checks: @[("database", s.dbHealthy), ("broker", broker)])

proc apiDeps*(s: Service): ApiDeps =
  ## The dependencies of `ledger/api.route`.
  ##
  ## **Description:** Task view, health and metrics of this service.
  ##
  ## **Business Justification:** Connects the API to the service.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ##
  ## **Returns:** the dependencies.
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
  ## **Example:** `await route(s.apiDeps(), "GET", "/health")`.
  ApiDeps(lookupTask: proc(taskId: string): Future[Option[JsonNode]] = s.taskView(taskId),
      health: proc(): Health = s.health(),
      metrics: proc(): string = s.metrics.render())

proc prepare*(s: Service) {.async.} =
  ## Applies the migrations, retrying until immudb is ready.
  ##
  ## **Description:** Retries with backoff (immudb may still be starting)
  ## until success or shutdown.
  ##
  ## **Business Justification:** Migrations at startup (CLAUDE.md 6.1).
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** DDL in immudb.
  ##
  ## **Complexity:** O(size of the migrations).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `waitFor s.prepare()` before `start`.
  var attempt = 0
  while not s.stopping:
    try:
      let applied = await migrate(s.db, s.cfg.migrationsDir, nowText())
      s.dbHealthy = true
      s.logger.log(lvInfo, "database ready", extra = [("applied", %applied)])
      return
    except CatchableError as e:
      inc attempt
      s.logger.log(lvWarn, "database not ready, retrying", extra = [
          ("error", %e.msg), ("attempt", %attempt)])
      await s.pause(attempt)

proc start*(s: Service) =
  ## Creates the Kafka consumer and producer.
  ##
  ## **Description:** Call after `prepare`, so that no event is consumed
  ## before the schema exists.
  ##
  ## **Business Justification:** See the module documentation.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** `KafkaError` for a rejected configuration.
  ##
  ## **Side Effects:** connects to the brokers.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `s.start()` after `prepare`.
  s.producer = newProducer(s.cfg.brokers, s.cfg.service, s.cfg.kafkaLogLevel, s.logger)
  s.consumer = newConsumer(s.cfg.brokers, s.cfg.consumerGroup, requestedTopic,
      s.cfg.service, s.cfg.kafkaLogLevel, s.logger)

proc recover*(s: Service) {.async.} =
  ## Publishes unpublished entries and resumes counting tasks.
  ##
  ## **Description:** Retries database failures until success or
  ## shutdown.
  ##
  ## **Business Justification:** Nothing is lost across restarts.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** Kafka messages; starts tasks.
  ##
  ## **Complexity:** O(unpublished entries + counting tasks).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `waitFor s.recover()` after `start`.
  var attempt = 0
  while not s.stopping:
    try:
      let entries = await s.db.unpublished()
      await s.appendLock.acquire()
      try:
        for e in entries:
          await s.publishEntry(e)
      finally:
        s.appendLock.release()
      let tasks = await s.db.countingTasks()
      for t in tasks:
        s.spawn(t)
      s.logger.log(lvInfo, "recovery done", extra = [("republished", %entries.len),
          ("resumed", %tasks.len)])
      return
    except CatchableError as e:
      inc attempt
      s.logger.log(lvWarn, "recovery failed, retrying", extra = [("error", %e.msg),
          ("attempt", %attempt)])
      await s.pause(attempt)

proc consumeLoop*(s: Service) {.async.} =
  ## Polls, processes and commits messages until shutdown.
  ##
  ## **Description:** One message at a time; sleeps 20 ms when idle.
  ##
  ## **Business Justification:** Step 1 of the module documentation.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** see `handleMessage`.
  ##
  ## **Complexity:** O(1) per message.
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `waitFor s.consumeLoop()` returns after `s.stopping` is set.
  while not s.stopping:
    let msg = s.consumer.poll()
    if msg.isNone:
      await sleepAsync(20)
      continue
    if await s.handleMessage(msg.get):
      s.consumer.commit(msg.get)
    else:
      release(msg.get)

proc serveLoop*(s: Service) {.async.} =
  ## Serves the producer's callbacks every 10 ms until shutdown.
  ##
  ## **Description:** Delivery reports must keep flowing while the consume
  ## loop waits on the database.
  ##
  ## **Business Justification:** `publish` completes promptly.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** runs callbacks.
  ##
  ## **Complexity:** O(1) per round.
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `let serving = s.serveLoop()` next to `consumeLoop`.
  while not s.stopping:
    s.producer.serve()
    await sleepAsync(10)

proc healthLoop*(s: Service) {.async.} =
  ## Checks the database every 5 s until shutdown.
  ##
  ## **Description:** Stores the result for `health`.
  ##
  ## **Business Justification:** `GET /health` answers at once, within
  ## the 2 s of the Compose health check.
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** one query every 5 s.
  ##
  ## **Complexity:** O(1) per round.
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `let checking = s.healthLoop()` at startup.
  while not s.stopping:
    s.dbHealthy = await s.db.healthy()
    var waited = 0
    while waited < 5000 and not s.stopping:
      await sleepAsync(100)
      waited += 100

proc drain*(s: Service, deadlineMs: int) {.async.} =
  ## Waits for running tasks to checkpoint, then closes Kafka.
  ##
  ## **Description:** Call after setting `stopping`. Tasks stop at their
  ## next successor call; the wait ends after `deadlineMs` regardless.
  ##
  ## **Business Justification:** Graceful shutdown within 10 s
  ## (CLAUDE.md 6.1).
  ##
  ## **Parameters:**
  ## - `s`: the service.
  ## - `deadlineMs`: the longest wait.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** checkpoints; closes the Kafka handles.
  ##
  ## **Complexity:** O(running tasks).
  ##
  ## **Thread Safety:** event loop only.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `s.stopping = true; waitFor s.drain(7000)`.
  let deadline = nowMillis() + deadlineMs
  while nowMillis() < deadline:
    var busy = false
    for f in s.running:
      busy = busy or not f.finished
    if not busy:
      break
    if s.producer != nil:
      s.producer.serve()
    await sleepAsync(20)
  if s.consumer != nil:
    s.consumer.close()
  if s.producer != nil:
    s.producer.close(1000)
