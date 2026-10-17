-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       parser
-- Module:          migrations/0001_initial_schema.sql
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Initial SQLite schema of the parser: the AST cache and the
--                  record of processed expression.submitted events.
-- Related Docs:    services/parser/README.md, CLAUDE.md 4.2 (idempotent
--                  consumers), ADR-0015
--
-- SQLite has no COMMENT ON statement (CLAUDE.md 6.5.3); every table and
-- column is documented by the comment directly above it, which SQLite also
-- keeps in sqlite_schema.sql, so `.schema` shows the documentation.

-- ast_cache: the AST of every expression text parsed successfully. An entry
-- never changes, because the AST depends only on the text.
CREATE TABLE ast_cache (
  -- The expression exactly as received in payload.expression (primary key).
  expression TEXT PRIMARY KEY NOT NULL,
  -- The AST serialized as JSON (Aaas_parser.Ast.to_json).
  ast_json TEXT NOT NULL,
  -- When the entry was created, UTC, ISO 8601 with milliseconds.
  created_at TEXT NOT NULL,
  -- How many times the entry answered a later parse of the same text.
  hits INTEGER NOT NULL DEFAULT 0
) STRICT;

-- processed_events: one row per consumed aaas.expression.submitted.v1 event,
-- keyed by its eventId, so that a redelivered event is never processed
-- twice (CLAUDE.md 4.2).
CREATE TABLE processed_events (
  -- eventId of the consumed event (lowercase UUIDv7, primary key).
  event_id TEXT PRIMARY KEY NOT NULL,
  -- taskId of the consumed event.
  task_id TEXT NOT NULL,
  -- pending: output stored, not yet acknowledged by the broker;
  -- published: output acknowledged; rejected: no output, see reason.
  status TEXT NOT NULL CHECK (status IN ('pending', 'published', 'rejected')),
  -- Why the expression was rejected; NULL unless status is rejected.
  reason TEXT,
  -- The aaas.addition.requested.v1 event produced for this input, exactly
  -- as published, so that a retry republishes the same eventId; NULL when
  -- rejected.
  output_event TEXT,
  -- When the event was first processed, UTC, ISO 8601 with milliseconds.
  processed_at TEXT NOT NULL,
  -- When the broker acknowledged the output; NULL until then.
  published_at TEXT
) STRICT;

-- processed_events_task: lookup of the outcome of a task during operations.
CREATE INDEX processed_events_task ON processed_events (task_id);
