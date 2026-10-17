(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Store
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         The parser's own SQLite database: migrations, the AST
                    cache and the record of processed events.
   Related Docs:    services/parser/migrations/, services/parser/README.md,
                    CLAUDE.md 4.2 and 6.1, ADR-0015
 *)

(** SQLite storage of the parser.

    {b Description:} One database file (default [/data/parser.db]) opened in WAL
    mode with [synchronous = FULL], so that a committed [processed_events] row
    survives a crash: losing it would make the parser publish a second event
    with a new [eventId] for the same task. Migrations from [migrations/*.sql]
    run at startup, each in its own transaction, and are recorded in
    [schema_migrations].

    {b Business Justification:} Every service owns its database (CLAUDE.md 1,
    rule 4); the parser's holds the AST cache (CLAUDE.md 2) and the idempotency
    record of its consumer (CLAUDE.md 4.2).

    {b Thread Safety:} a handle must be used by one system thread at a time; the
    service uses it from its single Lwt thread.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** A database failure.

    {b Description:} Carries the SQLite message and the statement context.

    {b Business Justification:} One exception for the processor to retry on
    ({!Processor}).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
exception Error of string

(** An open database.

    {b Description:} Wraps the SQLite handle.

    {b Business Justification:} Keeps the SQLite library out of the callers'
    signatures.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type t = { db : Sqlite3.db }

(** Status of a processed event.

    {b Description:} [Pending]: output stored, broker acknowledgement missing.
    [Published]: output acknowledged. [Rejected]: no output.

    {b Business Justification:} Decides what a redelivered event triggers (see
    {!Processor.handle}).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type status = Pending | Published | Rejected

(** The stored outcome of a processed event.

    {b Description:} [output_event] is the serialized
    [aaas.addition.requested.v1] event, absent for [Rejected].

    {b Business Justification:} A retry republishes exactly this text, so the
    produced [eventId] never changes.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type processed = { status : status; output_event : string option }

(** Raises {!Error} unless a return code is a success.

    {b Description:} [OK] and [DONE] are successes; the message includes
    SQLite's error message for the handle.

    {b Business Justification:} Every statement result is checked.

    {b Errors:} {!Error} for any other code.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      check t "ping" Sqlite3.Rc.OK = ()
    ]}

    {b See Also:} {!exec}.

    @param t the database.
    @param context what was being done, for the message.
    @param rc the return code.
    @raise Error on failure.
    @since parser 0.1.0 *)
let check t context rc =
  match rc with
  | Sqlite3.Rc.OK | Sqlite3.Rc.DONE -> ()
  | rc ->
      raise
        (Error
           (Printf.sprintf "%s: %s (%s)" context (Sqlite3.Rc.to_string rc)
              (Sqlite3.errmsg t.db)))

(** Runs SQL text without results.

    {b Description:} [sqlite3_exec]; the text may contain several statements.

    {b Business Justification:} Pragmas, migrations and transactions.

    {b Errors:} {!Error} on failure.

    {b Side Effects:} executes the statements.

    {b Complexity:} as the statements.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      exec t "pragma" "PRAGMA foreign_keys = ON"
    ]}

    {b See Also:} {!query}.

    @param t the database.
    @param context what is being done, for the message.
    @param sql the statements.
    @raise Error on failure.
    @since parser 0.1.0 *)
let exec t context sql = check t context (Sqlite3.exec t.db sql)

(** Runs one parameterised statement and collects its rows.

    {b Description:} Binds [params] as text or integer values (positions from
    1), steps through all rows and returns each row as an array of nullable text
    columns. The statement is always finalised.

    {b Business Justification:} Every query of the store goes through bound
    parameters; no value is ever spliced into SQL text.

    {b Errors:} {!Error} on a failed prepare, bind or step.

    {b Side Effects:} executes the statement.

    {b Complexity:} as the statement; O(r) memory in the rows returned.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      query t "ping" "SELECT 1" [] = [ [| Some "1" |] ]
    ]}

    {b See Also:} {!exec}.

    @param t the database.
    @param context what is being done, for the message.
    @param sql one statement with [?] placeholders.
    @param params the values of the placeholders, in order.
    @return the rows.
    @raise Error on failure.
    @since parser 0.1.0 *)
let query t context sql params =
  let stmt =
    try Sqlite3.prepare t.db sql
    with Sqlite3.Error message -> raise (Error (context ^ ": " ^ message))
  in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () ->
      List.iteri
        (fun i value ->
          let data =
            match value with
            | `Text s -> Sqlite3.Data.TEXT s
            | `Null -> Sqlite3.Data.NULL
          in
          check t context (Sqlite3.bind stmt (i + 1) data))
        params;
      let rec rows acc =
        match Sqlite3.step stmt with
        | Sqlite3.Rc.ROW ->
            let row =
              Array.init (Sqlite3.data_count stmt) (fun i ->
                  match Sqlite3.column stmt i with
                  | Sqlite3.Data.NULL -> None
                  | data -> Some (Sqlite3.Data.to_string_coerce data))
            in
            rows (row :: acc)
        | Sqlite3.Rc.DONE -> List.rev acc
        | rc ->
            check t context rc;
            List.rev acc
      in
      rows [])

(** Runs a function inside a transaction.

    {b Description:} [BEGIN IMMEDIATE], then [f ()], then [COMMIT]; any
    exception rolls back and is re-raised.

    {b Business Justification:} Migrations apply completely or not at all.

    {b Errors:} {!Error} from the transaction statements; any exception of [f].

    {b Side Effects:} executes [f] and the transaction statements.

    {b Complexity:} as [f].

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      transaction t "ping" (fun () -> query t "ping" "SELECT 1" [])
    ]}

    {b See Also:} {!migrate}.

    @param t the database.
    @param context what is being done, for the message.
    @param f the work.
    @return the result of [f].
    @raise Error on failure.
    @since parser 0.1.0 *)
let transaction t context f =
  exec t context "BEGIN IMMEDIATE";
  match f () with
  | result ->
      exec t context "COMMIT";
      result
  | exception e ->
      (try exec t context "ROLLBACK" with Error _ -> ());
      raise e

(** Opens (and creates if needed) the database file.

    {b Description:} Sets a 2 s busy timeout, WAL journal, [synchronous = FULL]
    and enforced foreign keys. Use [":memory:"] for a private in-memory database
    (tests).

    {b Business Justification:} Durable idempotency record (see the module
    documentation).

    {b Errors:} {!Error} if the file cannot be opened or the pragmas fail.

    {b Side Effects:} creates the file and its WAL files.

    {b Complexity:} O(1).

    {b Thread Safety:} returns a new handle.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      let t = open_db ":memory:" in
      ping t
    ]}

    {b See Also:} {!migrate}, {!close}.

    @param path the database file, or [":memory:"].
    @return the open database.
    @raise Error on failure.
    @since parser 0.1.0 *)
let open_db path =
  let db =
    try Sqlite3.db_open path
    with Sqlite3.Error message ->
      raise (Error ("open " ^ path ^ ": " ^ message))
  in
  let t = { db } in
  Sqlite3.busy_timeout db 2000;
  ignore (query t "journal mode" "PRAGMA journal_mode = WAL" []);
  exec t "pragmas" "PRAGMA synchronous = FULL; PRAGMA foreign_keys = ON";
  t

(** Closes the database.

    {b Description:} Closes the handle; later calls on [t] fail. A [false]
    result of SQLite (statements still open) is ignored because every statement
    of this module is finalised.

    {b Business Justification:} Graceful shutdown (CLAUDE.md 6.1).

    {b Errors:} None.

    {b Side Effects:} checkpoints and closes the file.

    {b Complexity:} O(size of the WAL).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      close (open_db ":memory:")
    ]}

    {b See Also:} {!open_db}.

    @param t the database.
    @since parser 0.1.0 *)
let close t = ignore (Sqlite3.db_close t.db)

(** Checks that the database answers a trivial query.

    {b Description:} [SELECT 1].

    {b Business Justification:} The [database] check of [GET /health].

    {b Errors:} None; a failure returns [false].

    {b Side Effects:} executes one query.

    {b Complexity:} O(1).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      ping (open_db ":memory:") = true
    ]}

    {b See Also:} {!Http.health}.

    @param t the database.
    @return [true] if the query succeeded.
    @since parser 0.1.0 *)
let ping t =
  match query t "ping" "SELECT 1" [] with
  | [ [| Some "1" |] ] -> true
  | _ -> false
  | exception Error _ -> false

(** Applies the migrations that have not been applied yet.

    {b Description:} Creates [schema_migrations] (the record of applied
    migrations: [version] is the file name, [applied_at] the time) if needed,
    then applies every [*.sql] file of [dir] in name order whose name is not
    recorded yet, each in its own transaction together with its record.

    {b Business Justification:} Migrations run at startup and are versioned in
    [migrations/] (CLAUDE.md 6.1).

    {b Errors:} {!Error} if a migration fails (nothing of it is applied);
    [Sys_error] if [dir] cannot be read.

    {b Side Effects:} changes the schema; reads [dir].

    {b Complexity:} O(m) in the number of migration files, plus their cost.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      migrate (open_db ":memory:") ~dir:"migrations" = 1
    ]}

    {b See Also:} services/parser/migrations/.

    @param t the database.
    @param dir the directory with the migration files.
    @return the number of migrations applied by this call.
    @raise Error if a migration fails.
    @since parser 0.1.0 *)
let migrate t ~dir =
  exec t "schema_migrations"
    "CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY \
     NOT NULL, applied_at TEXT NOT NULL) STRICT";
  let applied =
    query t "applied migrations" "SELECT version FROM schema_migrations" []
    |> List.filter_map (fun row -> row.(0))
  in
  Sys.readdir dir |> Array.to_list
  |> List.filter (fun name -> Filename.check_suffix name ".sql")
  |> List.sort compare
  |> List.filter (fun name -> not (List.mem name applied))
  |> List.fold_left
       (fun count name ->
         let sql =
           In_channel.with_open_bin (Filename.concat dir name)
             In_channel.input_all
         in
         transaction t ("migration " ^ name) (fun () ->
             exec t ("migration " ^ name) sql;
             ignore
               (query t "record migration"
                  "INSERT INTO schema_migrations (version, applied_at) VALUES \
                   (?, ?)"
                  [ `Text name; `Text (Timestamp.now ()) ]));
         count + 1)
       0

(** Looks up the cached AST of an expression text.

    {b Description:} On a hit, increments [hits] and decodes [ast_json]. An
    entry that does not decode (written by an incompatible version) counts as a
    miss.

    {b Business Justification:} The AST cache of CLAUDE.md 2: a repeated
    expression is not parsed again.

    {b Errors:} {!Error} on a database failure.

    {b Side Effects:} one read and, on a hit, one update.

    {b Complexity:} O(log n) in the number of entries.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      cache_find t "2+3" = None
    ]}

    {b See Also:} {!cache_put}, {!Ast.of_json}.

    @param t the database.
    @param expression the expression text.
    @return the AST, or [None] on a miss.
    @raise Error on a database failure.
    @since parser 0.1.0 *)
let cache_find t expression =
  match
    query t "cache lookup" "SELECT ast_json FROM ast_cache WHERE expression = ?"
      [ `Text expression ]
  with
  | [ [| Some json |] ] -> (
      match Ast.of_json (Yojson.Safe.from_string json) with
      | Ok ast ->
          ignore
            (query t "cache hit"
               "UPDATE ast_cache SET hits = hits + 1 WHERE expression = ?"
               [ `Text expression ]);
          Some ast
      | Error _ -> None
      | exception Yojson.Json_error _ -> None)
  | _ -> None

(** Stores the AST of an expression text.

    {b Description:} Inserts the entry unless one exists ([INSERT OR IGNORE]):
    an AST depends only on the text, so an existing entry is already right.

    {b Business Justification:} Fills the AST cache.

    {b Errors:} {!Error} on a database failure.

    {b Side Effects:} at most one insert.

    {b Complexity:} O(log n).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      cache_put t "2+3" ast
    ]}

    {b See Also:} {!cache_find}, {!Ast.to_json}.

    @param t the database.
    @param expression the expression text.
    @param ast its AST.
    @raise Error on a database failure.
    @since parser 0.1.0 *)
let cache_put t expression ast =
  ignore
    (query t "cache store"
       "INSERT OR IGNORE INTO ast_cache (expression, ast_json, created_at) \
        VALUES (?, ?, ?)"
       [
         `Text expression;
         `Text (Yojson.Safe.to_string (Ast.to_json ast));
         `Text (Timestamp.now ());
       ])

(** Looks up a consumed event by its [eventId].

    {b Description:} Returns the stored status and output, if the event was
    processed before.

    {b Business Justification:} Idempotent consumer (CLAUDE.md 4.2).

    {b Errors:} {!Error} on a database failure or an unknown stored status.

    {b Side Effects:} one read.

    {b Complexity:} O(log n).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      find_processed t "018f3c2e-7b1a-7c3d-9f00-000000000010" = None
    ]}

    {b See Also:} {!record_pending}, {!record_rejected}.

    @param t the database.
    @param event_id the consumed event's identifier.
    @return the stored outcome, if any.
    @raise Error on a database failure.
    @since parser 0.1.0 *)
let find_processed t event_id =
  match
    query t "processed lookup"
      "SELECT status, output_event FROM processed_events WHERE event_id = ?"
      [ `Text event_id ]
  with
  | [] -> None
  | [ [| Some status; output_event |] ] ->
      let status =
        match status with
        | "pending" -> Pending
        | "published" -> Published
        | "rejected" -> Rejected
        | other -> raise (Error ("processed lookup: unknown status " ^ other))
      in
      Some { status; output_event }
  | _ -> raise (Error "processed lookup: unexpected result")

(** Records a consumed event whose output is about to be published.

    {b Description:} Inserts the row with status [pending] and the output event
    text. Must happen before publishing, so that a retry finds and republishes
    the same output.

    {b Business Justification:} Exactly one produced [eventId] per consumed
    event, even across crashes.

    {b Errors:} {!Error} on a database failure, including a duplicate
    [event_id].

    {b Side Effects:} one insert.

    {b Complexity:} O(log n).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      record_pending t ~event_id ~task_id ~output_event:"{...}"
    ]}

    {b See Also:} {!mark_published}.

    @param t the database.
    @param event_id the consumed event's identifier.
    @param task_id its task.
    @param output_event the serialized output event.
    @raise Error on a database failure.
    @since parser 0.1.0 *)
let record_pending t ~event_id ~task_id ~output_event =
  ignore
    (query t "record pending"
       "INSERT INTO processed_events (event_id, task_id, status, output_event, \
        processed_at) VALUES (?, ?, 'pending', ?, ?)"
       [
         `Text event_id;
         `Text task_id;
         `Text output_event;
         `Text (Timestamp.now ());
       ])

(** Records a consumed event whose expression was rejected.

    {b Description:} Inserts the row with status [rejected] and the reason.

    {b Business Justification:} A redelivered rejected event is not evaluated
    again, and support can look up why a task has no result.

    {b Errors:} {!Error} on a database failure, including a duplicate
    [event_id].

    {b Side Effects:} one insert.

    {b Complexity:} O(log n).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      record_rejected t ~event_id ~task_id ~reason:"missing_operator: ..."
    ]}

    {b See Also:} {!find_processed}.

    @param t the database.
    @param event_id the consumed event's identifier.
    @param task_id its task.
    @param reason code and description of the rejection.
    @raise Error on a database failure.
    @since parser 0.1.0 *)
let record_rejected t ~event_id ~task_id ~reason =
  ignore
    (query t "record rejected"
       "INSERT INTO processed_events (event_id, task_id, status, reason, \
        processed_at) VALUES (?, ?, 'rejected', ?, ?)"
       [ `Text event_id; `Text task_id; `Text reason; `Text (Timestamp.now ()) ])

(** Marks the output of a consumed event as acknowledged by the broker.

    {b Description:} Sets status [published] and [published_at]; a no-op for a
    row that is not [pending].

    {b Business Justification:} Distinguishes a finished event from one whose
    output must be republished.

    {b Errors:} {!Error} on a database failure.

    {b Side Effects:} at most one update.

    {b Complexity:} O(log n).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      mark_published t ~event_id
    ]}

    {b See Also:} {!record_pending}.

    @param t the database.
    @param event_id the consumed event's identifier.
    @raise Error on a database failure.
    @since parser 0.1.0 *)
let mark_published t ~event_id =
  ignore
    (query t "mark published"
       "UPDATE processed_events SET status = 'published', published_at = ? \
        WHERE event_id = ? AND status = 'pending'"
       [ `Text (Timestamp.now ()); `Text event_id ])
