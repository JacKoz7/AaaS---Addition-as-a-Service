-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       ledger
-- Module:          migrations/0001_initial_schema.sql
-- Owning Team:     Transaction Integrity Office (TIO)
-- Classification:  INTERNAL
-- Purpose:         Initial schema of the ledger database in immudb: processed
--                  events, counting tasks, the hash-chained ledger entries,
--                  their publications and the documentation of every table
--                  and column.
-- Related Docs:    services/ledger/README.md (Database), ADR-0013, ADR-0017
--
-- Dialect: immudb SQL. The migration runner (ledger/store.nim) removes the
-- lines that start with `--`, wraps the file in one transaction together
-- with its row in schema_migrations, and sends it in one call. immudb has no
-- COMMENT ON; the table schema_documentation holds the description of every
-- table and column instead (CLAUDE.md 6.5.3), and `sequence` is a reserved
-- word in immudb, hence `entry_seq`. immudb keeps every version of every row,
-- so an UPDATE never loses history.

CREATE TABLE schema_documentation (
  object_name VARCHAR[128] NOT NULL,
  description VARCHAR[1024] NOT NULL,
  PRIMARY KEY object_name
);

-- Idempotency of the consumer (CLAUDE.md 4.2): one row per consumed event.
CREATE TABLE processed_events (
  event_id VARCHAR[36] NOT NULL,
  task_id VARCHAR[36] NOT NULL,
  topic VARCHAR[64] NOT NULL,
  processed_at VARCHAR[24] NOT NULL,
  PRIMARY KEY event_id
);

-- One row per addition task; updated at every checkpoint.
CREATE TABLE tasks (
  task_id VARCHAR[36] NOT NULL,
  a INTEGER NOT NULL,
  b INTEGER NOT NULL,
  status VARCHAR[16] NOT NULL,
  done INTEGER NOT NULL,
  current INTEGER NOT NULL,
  result INTEGER,
  traceparent VARCHAR[55] NOT NULL,
  failure VARCHAR[512] NOT NULL,
  accepted_at VARCHAR[24] NOT NULL,
  updated_at VARCHAR[24] NOT NULL,
  PRIMARY KEY task_id
);
CREATE INDEX ON tasks(status);

-- The hash chain: insert-only, one entry per task.
CREATE TABLE ledger_entries (
  entry_seq INTEGER NOT NULL,
  task_id VARCHAR[36] NOT NULL,
  a INTEGER NOT NULL,
  b INTEGER NOT NULL,
  result INTEGER NOT NULL,
  recorded_at VARCHAR[24] NOT NULL,
  prev_hash VARCHAR[64] NOT NULL,
  hash VARCHAR[64] NOT NULL,
  event_id VARCHAR[36] NOT NULL,
  event VARCHAR[2048] NOT NULL,
  PRIMARY KEY entry_seq
);
CREATE UNIQUE INDEX ON ledger_entries(task_id);

-- Acknowledged publications of aaas.ledger.appended.v1: insert-only.
CREATE TABLE publications (
  entry_seq INTEGER NOT NULL,
  published_at VARCHAR[24] NOT NULL,
  PRIMARY KEY entry_seq
);

INSERT INTO schema_documentation (object_name, description) VALUES
  ('schema_migrations', 'Migrations applied to this database, one row per file of migrations/; created by the migration runner before the first migration.'),
  ('schema_migrations.version', 'File name of the migration without .sql, e.g. 0001_initial_schema.'),
  ('schema_migrations.applied_at', 'When the migration was applied (UTC, millisecond ISO 8601).'),
  ('schema_documentation', 'Description of every table and column of the ledger database; immudb has no COMMENT ON.'),
  ('schema_documentation.object_name', 'Table name, or table.column.'),
  ('schema_documentation.description', 'What the object holds and why.'),
  ('processed_events', 'Idempotency of the consumer: one row per consumed event, written in the same transaction as the task it creates (CLAUDE.md 4.2).'),
  ('processed_events.event_id', 'eventId of the consumed event (lowercase UUIDv7).'),
  ('processed_events.task_id', 'taskId of the consumed event.'),
  ('processed_events.topic', 'Topic the event was consumed from.'),
  ('processed_events.processed_at', 'When the event was processed (UTC, millisecond ISO 8601).'),
  ('tasks', 'One row per addition task: operands, status and the last checkpoint of the Peano loop. TEMPORARY(P3.3): the saga-orchestrator owns task status from P3.3.'),
  ('tasks.task_id', 'The task (lowercase UUIDv7), key of the row.'),
  ('tasks.a', 'First operand, 0..99999.'),
  ('tasks.b', 'Second operand, 0..99999: the number of successor calls.'),
  ('tasks.status', 'COUNTING until the entry is appended, then RECORDED; FAILED if the successor refused a call.'),
  ('tasks.done', 'Successor calls made at the last checkpoint, 0..b.'),
  ('tasks.current', 'Value after done successor calls (a when done = 0).'),
  ('tasks.result', 'The sum once RECORDED, otherwise NULL.'),
  ('tasks.traceparent', 'traceparent of the event that created the task, or empty: successor calls and the published event continue this trace.'),
  ('tasks.failure', 'Why the task FAILED, or empty.'),
  ('tasks.accepted_at', 'When the task was created from its event (UTC, millisecond ISO 8601).'),
  ('tasks.updated_at', 'When the row last changed.'),
  ('ledger_entries', 'The hash chain: one insert-only entry per recorded addition, ordered by entry_seq without gaps (ADR-0013).'),
  ('ledger_entries.entry_seq', 'Position in the chain, from 1 (the sequence of aaas.ledger.appended.v1).'),
  ('ledger_entries.task_id', 'The task; unique, so a task is recorded at most once.'),
  ('ledger_entries.a', 'First operand.'),
  ('ledger_entries.b', 'Second operand.'),
  ('ledger_entries.result', 'Recorded sum, computed by successor calls.'),
  ('ledger_entries.recorded_at', 'When the entry was appended; part of the hashed content.'),
  ('ledger_entries.prev_hash', 'hash of the previous entry; 64 zeros for entry 1.'),
  ('ledger_entries.hash', 'SHA-256 of prev_hash|task_id|a|b|result|recorded_at (ADR-0013), lowercase hex.'),
  ('ledger_entries.event_id', 'eventId of the aaas.ledger.appended.v1 event of the entry.'),
  ('ledger_entries.event', 'That event as published (JSON text); republished unchanged after a restart.'),
  ('publications', 'Acknowledged publications of aaas.ledger.appended.v1: an entry without a row here is published again at startup.'),
  ('publications.entry_seq', 'The published entry.'),
  ('publications.published_at', 'When the broker acknowledged the event.');
