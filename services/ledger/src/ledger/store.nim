# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/store
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Persistence of the ledger in immudb: migrations, processed
#                  events, tasks, ledger entries and publications.
# Related Docs:    services/ledger/migrations/0001_initial_schema.sql,
#                  services/ledger/README.md (Database), ADR-0017

## The ledger database.
##
## **Description:** Every read and write of the service goes through this
## module. Writes that belong together are one immudb transaction: a
## consumed event and the task it creates; a ledger entry and the task
## status. Unique keys make every write safe to repeat after a timeout:
## `processed_events.event_id`, `tasks.task_id`, `ledger_entries.entry_seq`
## and `ledger_entries.task_id`, `publications.entry_seq`.
##
## **Business Justification:** The ledger is the system of record of every
## result (CLAUDE.md 3, step 10) and must survive restarts without counting
## twice or recording twice.
##
## **Thread Safety:** not thread-safe; used from the event loop only.
## Appends must be serialized by the caller (`ledger/service`).
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[algorithm, asyncdispatch, json, options, os, strutils]
import events, immudb, peano

type
  TaskStatus* = enum
    ## Status of a task as stored.
    ##
    ## **Description:** `RECORDING` exists only in memory, between the end
    ## of counting and the append (`ledger/service`).
    ##
    ## **Business Justification:** The statuses of CLAUDE.md 4.1 that the
    ## ledger can observe.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    tsCounting = "COUNTING" ## Successor calls in progress.
    tsRecording = "RECORDING" ## Counted; the entry is being appended.
    tsRecorded = "RECORDED" ## The entry is in the ledger.
    tsFailed = "FAILED" ## The successor refused a call.

  TaskRow* = object
    ## A row of `tasks`.
    ##
    ## **Description:** See `schema_documentation`.
    ##
    ## **Business Justification:** Answers `GET /api/v1/tasks/{taskId}` and
    ## resumes counting after a restart.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    taskId*: string ## The task.
    a*: int64 ## First operand.
    b*: int64 ## Second operand.
    status*: TaskStatus ## Stored status.
    state*: CountState ## Last checkpoint.
    sum*: Option[int64] ## The result once recorded.
    traceparent*: string ## traceparent of the creating event, or empty.

  AcceptOutcome* = enum
    ## What `acceptEvent` did with an event.
    ##
    ## **Description:** Only `aoNewTask` starts counting.
    ##
    ## **Business Justification:** Metrics and logs per outcome.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    aoNewTask = "new_task" ## Event and task stored.
    aoDuplicateEvent = "duplicate" ## The eventId was processed before.
    aoKnownTask = "known_task" ## New eventId for an existing task (a republication).

  StoredEntry* = object
    ## A ledger entry with its serialized event.
    ##
    ## **Description:** What `appendEntry` wrote.
    ##
    ## **Business Justification:** Republication after a restart.
    ##
    ## **Owner:** Transaction Integrity Office (TIO).
    ##
    ## **Since:** ledger 0.1.0
    entry*: LedgerEntry ## The entry.
    eventId*: string ## eventId of its event.
    event*: string ## The event as published.

proc stripComments*(sql: string): string =
  ## Removes the lines that start with `--` (after indentation).
  ##
  ## **Description:** immudb SQL does not accept `--` comments, but the
  ## migration files carry the mandatory header in them.
  ##
  ## **Business Justification:** Documented migrations (CLAUDE.md 6.5.2).
  ##
  ## **Parameters:**
  ## - `sql`: the file text.
  ##
  ## **Returns:** the text without comment lines.
  ##
  ## **Errors:** None.
  ##
  ## **Side Effects:** None.
  ##
  ## **Complexity:** O(size of the text).
  ##
  ## **Thread Safety:** safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  runnableExamples:
    doAssert stripComments("-- header\nCREATE TABLE t (k INTEGER);\n  -- note\n") ==
      "CREATE TABLE t (k INTEGER);\n"
  for line in sql.splitLines(keepEol = true):
    if not line.strip.startsWith("--"):
      result.add(line)

proc migrate*(db: ImmuClient, dir, now: string): Future[seq[string]] {.async.} =
  ## Applies the migrations of `dir` that are not applied yet.
  ##
  ## **Description:** Creates `schema_migrations` if missing, then applies
  ## every `*.sql` file in name order whose name (without `.sql`) has no
  ## row, each in one transaction with its row. A concurrent runner that
  ## applied the same migration makes the transaction fail on the
  ## duplicate row, which is treated as applied.
  ##
  ## **Business Justification:** Migrations at startup (CLAUDE.md 6.1).
  ##
  ## **Parameters:**
  ## - `db`: the client.
  ## - `dir`: the migrations directory.
  ## - `now`: the timestamp for `applied_at`.
  ##
  ## **Returns:** the versions applied by this call.
  ##
  ## **Errors:** `ImmuError` for an invalid migration, `ImmuUnavailable`,
  ## `OSError` if a file cannot be read.
  ##
  ## **Side Effects:** DDL and inserts in immudb.
  ##
  ## **Complexity:** O(total size of the migrations).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `discard await migrate(db, "/app/migrations", formatTimestamp(nowMillis()))`.
  await db.exec("CREATE TABLE IF NOT EXISTS schema_migrations (" &
      "version VARCHAR[64] NOT NULL, applied_at VARCHAR[24] NOT NULL, PRIMARY KEY version);")
  var applied: seq[string]
  for row in await db.query("SELECT version FROM schema_migrations"):
    applied.add(row[0].getStr)
  var files: seq[string]
  for f in walkFiles(dir / "*.sql"):
    files.add(f)
  files.sort()
  for f in files:
    let version = f.extractFilename.changeFileExt("")
    if version in applied:
      continue
    let sql = "BEGIN TRANSACTION;\n" & stripComments(readFile(f)) &
        "\nINSERT INTO schema_migrations (version, applied_at) VALUES (@version, @at);\nCOMMIT;"
    try:
      await db.exec(sql, [("version", %version), ("at", %now)])
      result.add(version)
    except ImmuError as e:
      if not e.isDuplicate:
        raise

proc rowToTask(r: seq[JsonNode]): TaskRow =
  ## A `tasks` row selected in the order of `taskColumns`.
  ##
  ## **Description:** Helper of the task queries.
  ##
  ## **Business Justification:** One decoding for every query.
  ##
  ## **Parameters:**
  ## - `r`: the values.
  ##
  ## **Returns:** the task.
  ##
  ## **Errors:** `ValueError` for an unknown status.
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
  TaskRow(taskId: r[0].getStr, a: r[1].getBiggestInt, b: r[2].getBiggestInt,
      status: parseEnum[TaskStatus](r[3].getStr),
      state: CountState(done: r[4].getBiggestInt, current: r[5].getBiggestInt),
      sum: (if r[6].kind == JInt: some(r[6].getBiggestInt) else: none(int64)),
      traceparent: r[7].getStr)

const taskColumns = "task_id, a, b, status, done, current, result, traceparent"
  ## Select list of `rowToTask`.
  ##
  ## **Description:** Order matters.
  ##
  ## **Business Justification:** Keeps queries and decoding in step.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0

proc getTask*(db: ImmuClient, taskId: string): Future[Option[TaskRow]] {.async.} =
  ## The task `taskId`, if known.
  ##
  ## **Description:** Reads the current version of the row.
  ##
  ## **Business Justification:** `GET /api/v1/tasks/{taskId}`.
  ##
  ## **Parameters:**
  ## - `db`: the client.
  ## - `taskId`: the task.
  ##
  ## **Returns:** the row, or `none`.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** one query.
  ##
  ## **Complexity:** O(log n) in the database (primary key).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `let t = await db.getTask(taskId)`; `t.get.status == tsCounting` while counting.
  let rows = await db.query("SELECT " & taskColumns &
      " FROM tasks WHERE task_id = @t", [("t", %taskId)])
  return (if rows.len == 0: none(TaskRow) else: some(rowToTask(rows[0])))

proc countingTasks*(db: ImmuClient): Future[seq[TaskRow]] {.async.} =
  ## Every task still `COUNTING`.
  ##
  ## **Description:** Uses the index on `status`.
  ##
  ## **Business Justification:** Resumed after a restart.
  ##
  ## **Parameters:**
  ## - `db`: the client.
  ##
  ## **Returns:** the rows.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** one query.
  ##
  ## **Complexity:** O(k log n) for k counting tasks.
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `for t in await db.countingTasks(): resume(t)`.
  for r in await db.query("SELECT " & taskColumns &
      " FROM tasks WHERE status = 'COUNTING'"):
    result.add(rowToTask(r))

proc acceptEvent*(db: ImmuClient, ev: AdditionRequested, now: string): Future[
    AcceptOutcome] {.async.} =
  ## Stores a consumed event and, for a new task, the task.
  ##
  ## **Description:** A known `eventId` is a duplicate delivery. A new
  ## `eventId` for a known task (the parser republishes after losing its
  ## database) is recorded and ignored, so that one task is counted once.
  ## Otherwise the event and a `COUNTING` task with `done = 0, current = a`
  ## are inserted in one transaction. A duplicate-key failure (a repeated
  ## insert after a timeout) is resolved by deciding again.
  ##
  ## **Business Justification:** Idempotent consumer (CLAUDE.md 4.2),
  ## keyed by `eventId` with `taskId` as the unit of work.
  ##
  ## **Parameters:**
  ## - `db`: the client.
  ## - `ev`: the decoded event.
  ## - `now`: the timestamp for the rows.
  ##
  ## **Returns:** the outcome.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** up to one transaction.
  ##
  ## **Complexity:** O(1) queries.
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  for _ in 1 .. 2:
    let seen = await db.query("SELECT event_id FROM processed_events WHERE event_id = @e",
        [("e", %ev.eventId)])
    if seen.len > 0:
      return aoDuplicateEvent
    let eventRow = "INSERT INTO processed_events (event_id, task_id, topic, processed_at) " &
        "VALUES (@e, @t, @topic, @now);"
    let params = @[("e", %ev.eventId), ("t", %ev.taskId), ("topic", %requestedTopic),
        ("now", %now), ("a", %ev.a), ("b", %ev.b), ("tp", %ev.traceparent)]
    try:
      if (await db.getTask(ev.taskId)).isSome:
        await db.exec(eventRow, params)
        return aoKnownTask
      await db.exec("BEGIN TRANSACTION;\n" & eventRow &
          "\nINSERT INTO tasks (task_id, a, b, status, done, current, traceparent, failure, accepted_at, updated_at) " &
          "VALUES (@t, @a, @b, 'COUNTING', 0, @a, @tp, '', @now, @now);\nCOMMIT;", params)
      return aoNewTask
    except ImmuError as e:
      if not e.isDuplicate:
        raise
  return aoDuplicateEvent

proc checkpoint*(db: ImmuClient, taskId: string, state: CountState,
    now: string) {.async.} =
  ## Stores the progress of a counting task.
  ##
  ## **Description:** Updates `done`, `current` and `updated_at` of a
  ## `COUNTING` task (immudb keeps the previous versions).
  ##
  ## **Business Justification:** A restart resumes from here.
  ##
  ## **Parameters:**
  ## - `db`: the client.
  ## - `taskId`: the task.
  ## - `state`: the progress.
  ## - `now`: the timestamp.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** one transaction.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  await db.exec("UPDATE tasks SET done = @d, current = @c, updated_at = @now " &
      "WHERE task_id = @t AND status = 'COUNTING';", [("d", %state.done),
      ("c", %state.current), ("now", %now), ("t", %taskId)])

proc markFailed*(db: ImmuClient, taskId, reason, now: string) {.async.} =
  ## Marks a counting task `FAILED`.
  ##
  ## **Description:** The reason is truncated to 500 characters.
  ##
  ## **Business Justification:** A task the successor refuses can never
  ## be recorded; its status must say so.
  ##
  ## **Parameters:**
  ## - `db`: the client.
  ## - `taskId`: the task.
  ## - `reason`: why.
  ## - `now`: the timestamp.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** one transaction.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `await db.markFailed(taskId, "successor refused n = 5", now)`.
  await db.exec("UPDATE tasks SET status = 'FAILED', failure = @r, updated_at = @now " &
      "WHERE task_id = @t AND status = 'COUNTING';", [("r", %reason[0 ..< min(
      reason.len, 500)]), ("now", %now), ("t", %taskId)])

const entryColumns = "entry_seq, task_id, a, b, result, recorded_at, prev_hash, hash, event_id, event"
  ## Select list of `rowToEntry`.
  ##
  ## **Description:** Order matters.
  ##
  ## **Business Justification:** Keeps queries and decoding in step.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0

proc rowToEntry(r: seq[JsonNode]): StoredEntry =
  ## A `ledger_entries` row selected in the order of `entryColumns`.
  ##
  ## **Description:** Helper of the entry queries.
  ##
  ## **Business Justification:** One decoding for every query.
  ##
  ## **Parameters:**
  ## - `r`: the values.
  ##
  ## **Returns:** the stored entry.
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
  StoredEntry(entry: LedgerEntry(sequence: r[0].getBiggestInt,
      taskId: r[1].getStr, a: r[2].getBiggestInt, b: r[3].getBiggestInt,
      sum: r[4].getBiggestInt, recordedAt: r[5].getStr, prevHash: r[6].getStr,
      hash: r[7].getStr), eventId: r[8].getStr, event: r[9].getStr)

proc lastEntry*(db: ImmuClient): Future[Option[StoredEntry]] {.async.} =
  ## The entry with the highest `entry_seq`, if any.
  ##
  ## **Description:** The link target of the next append.
  ##
  ## **Business Justification:** The chain grows from its end.
  ##
  ## **Parameters:**
  ## - `db`: the client.
  ##
  ## **Returns:** the entry, or `none` for an empty ledger.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** one query.
  ##
  ## **Complexity:** O(log n).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `let last = await db.lastEntry()`; `none` for an empty ledger.
  let rows = await db.query("SELECT " & entryColumns &
      " FROM ledger_entries ORDER BY entry_seq DESC LIMIT 1")
  return (if rows.len == 0: none(StoredEntry) else: some(rowToEntry(rows[0])))

proc entryOfTask*(db: ImmuClient, taskId: string): Future[Option[
    StoredEntry]] {.async.} =
  ## The entry of a task, if recorded.
  ##
  ## **Description:** Uses the unique index on `task_id`.
  ##
  ## **Business Justification:** Resolves a repeated append after a
  ## timeout.
  ##
  ## **Parameters:**
  ## - `db`: the client.
  ## - `taskId`: the task.
  ##
  ## **Returns:** the entry, or `none`.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** one query.
  ##
  ## **Complexity:** O(log n).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  let rows = await db.query("SELECT " & entryColumns &
      " FROM ledger_entries WHERE task_id = @t", [("t", %taskId)])
  return (if rows.len == 0: none(StoredEntry) else: some(rowToEntry(rows[0])))

proc appendEntry*(db: ImmuClient, stored: StoredEntry, now: string) {.async.} =
  ## Appends an entry and marks its task `RECORDED`, in one transaction.
  ##
  ## **Description:** The entry must link to `lastEntry` (the caller holds
  ## the append lock). The primary key on `entry_seq` and the unique index
  ## on `task_id` reject a second entry at the same position or for the
  ## same task.
  ##
  ## **Business Justification:** CLAUDE.md 3, step 10.
  ##
  ## **Parameters:**
  ## - `db`: the client.
  ## - `stored`: the entry and its event.
  ## - `now`: the timestamp for `updated_at`.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** `ImmuError` (duplicate for an existing position or
  ## task), `ImmuUnavailable`.
  ##
  ## **Side Effects:** one transaction.
  ##
  ## **Complexity:** O(log n).
  ##
  ## **Thread Safety:** not thread-safe; serialize appends.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `await db.appendEntry(StoredEntry(entry: e, eventId: id, event: json), now)`.
  let e = stored.entry
  await db.exec("BEGIN TRANSACTION;\n" &
      "INSERT INTO ledger_entries (" & entryColumns &
      ") VALUES (@s, @t, @a, @b, @r, @at, @prev, @h, @eid, @ev);\n" &
      "UPDATE tasks SET status = 'RECORDED', result = @r, done = @b, current = @r, updated_at = @now WHERE task_id = @t;\n" &
      "COMMIT;", [("s", %e.sequence), ("t", %e.taskId), ("a", %e.a), ("b", %e.b),
      ("r", %e.sum), ("at", %e.recordedAt), ("prev", %e.prevHash), ("h", %e.hash),
      ("eid", %stored.eventId), ("ev", %stored.event), ("now", %now)])

proc markPublished*(db: ImmuClient, sequence: int64, now: string) {.async.} =
  ## Records that the event of entry `sequence` was acknowledged.
  ##
  ## **Description:** A repeated call is ignored.
  ##
  ## **Business Justification:** Entries without a publication are
  ## published again at startup.
  ##
  ## **Parameters:**
  ## - `db`: the client.
  ## - `sequence`: the entry.
  ## - `now`: the acknowledgement timestamp.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** `ImmuError` (other than a duplicate), `ImmuUnavailable`.
  ##
  ## **Side Effects:** one insert.
  ##
  ## **Complexity:** O(log n).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `await db.markPublished(entry.sequence, now)` after the acknowledgement.
  try:
    await db.exec("INSERT INTO publications (entry_seq, published_at) VALUES (@s, @now);",
        [("s", %sequence), ("now", %now)])
  except ImmuError as e:
    if not e.isDuplicate:
      raise

proc unpublished*(db: ImmuClient): Future[seq[StoredEntry]] {.async.} =
  ## Entries after the last acknowledged publication, in chain order.
  ##
  ## **Description:** Entries are published in chain order under the
  ## append lock, so every entry after the highest published one is
  ## unpublished.
  ##
  ## **Business Justification:** At-least-once publication of
  ## `aaas.ledger.appended.v1` across restarts.
  ##
  ## **Parameters:**
  ## - `db`: the client.
  ##
  ## **Returns:** the entries.
  ##
  ## **Errors:** `ImmuError`, `ImmuUnavailable`.
  ##
  ## **Side Effects:** two queries.
  ##
  ## **Complexity:** O(k log n) for k unpublished entries.
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `for e in await db.unpublished(): await publish(e)`.
  let top = await db.query("SELECT entry_seq FROM publications ORDER BY entry_seq DESC LIMIT 1")
  let last = if top.len == 0: 0'i64 else: top[0][0].getBiggestInt
  for r in await db.query("SELECT " & entryColumns &
      " FROM ledger_entries WHERE entry_seq > @s ORDER BY entry_seq", [("s", %last)]):
    result.add(rowToEntry(r))
