(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Processor
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Processes one consumed aaas.expression.submitted.v1
                    message: idempotency check, parsing through the AST
                    cache, and publication of aaas.addition.requested.v1.
   Related Docs:    services/parser/README.md, services/parser/docs/API.md,
                    CLAUDE.md 3 (step 4) and 4.2, ADR-0015
 *)

(** Message processing of the parser.

    {b Description:} {!handle} turns one message into one {!outcome}:
    + decode the event; a message that is not an [aaas.expression.submitted.v1]
      event is [Discarded];
    + look up its [eventId] in [processed_events]: a [published] or [rejected]
      event is a [Duplicate]; a [pending] one has its stored output published
      again ([Republished]);
    + otherwise parse the expression, through the AST cache; a syntax or range
      error is recorded and [Rejected];
    + otherwise build the output event, store it as [pending], publish it keyed
      by [taskId], and mark it [published] ([Published]).

    Database and broker failures are not outcomes: they raise, and the caller
    retries the same message ({!Consumer}). Because the output is stored before
    it is published, every retry publishes the identical event, so a consumed
    event yields exactly one produced [eventId].

    {b Business Justification:} Step 4 of the request flow (CLAUDE.md 3), with
    the idempotent consumer of CLAUDE.md 4.2.

    {b Thread Safety:} one message at a time per store.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** The result of processing one message.

    {b Description:}
    - [Published]: a new addition was requested ([cache_hit] tells whether the
      AST came from the cache);
    - [Republished]: the stored output of an earlier attempt was published;
    - [Duplicate]: the event was processed before; nothing was done;
    - [Rejected]: the expression is not a valid addition ([code] and [message]
      say why); nothing was published;
    - [Discarded]: the message is not an expression event at all.

    {b Business Justification:} Feeds the metrics and the log, and lets the
    tests assert the behaviour.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type outcome =
  | Published of { task_id : string; a : int; b : int; cache_hit : bool }
  | Republished of { task_id : string }
  | Duplicate of { task_id : string }
  | Rejected of { task_id : string; code : string; message : string }
  | Discarded of { reason : string }

(** Publishes one message and resolves on the broker's acknowledgement.

    {b Description:} [publish ~key value] sends [value] to
    [aaas.addition.requested.v1] with the given key; it fails (rejects the
    promise) if the message is not acknowledged.

    {b Business Justification:} Abstracts Kafka so that the processor can be
    tested without a broker.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type publisher = key:string -> string -> unit Lwt.t

(** Label value of an outcome for [parser_events_consumed_total].

    {b Description:} [published], [republished], [duplicate], [rejected] or
    [discarded].

    {b Business Justification:} One time series per outcome.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      outcome_label (Duplicate { task_id = "t" }) = "duplicate"
    ]}

    {b See Also:} {!Metrics.events_consumed}.

    @param outcome an outcome.
    @return its label value.
    @since parser 0.1.0 *)
let outcome_label = function
  | Published _ -> "published"
  | Republished _ -> "republished"
  | Duplicate _ -> "duplicate"
  | Rejected _ -> "rejected"
  | Discarded _ -> "discarded"

(** Parses an expression, using and filling the AST cache.

    {b Description:} A cache hit returns the stored AST; on a miss the text is
    parsed with {!Grammar.parse} and a successful result is cached. Rejections
    are not cached: parsing them again is as cheap as a lookup.

    {b Business Justification:} The AST cache of the parser database (CLAUDE.md
    2).

    {b Errors:} [Error e] for a syntax error.

    {b Side Effects:} reads and writes [ast_cache]; increments
    [parser_ast_cache_lookups_total].

    {b Complexity:} O(n) in the length of the expression.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      parse_cached store "2+3" = (Ok ast, false)
    ]}

    {b See Also:} {!Store.cache_find}, {!Store.cache_put}.

    @param store the parser database.
    @param expression the expression text.
    @return the parse result and whether it was a cache hit.
    @raise Store.Error on a database failure.
    @since parser 0.1.0 *)
let parse_cached store expression =
  match Store.cache_find store expression with
  | Some ast ->
      Metrics.inc ~labels:[ ("result", "hit") ] Metrics.ast_cache_lookups;
      (Ok ast, true)
  | None -> (
      Metrics.inc ~labels:[ ("result", "miss") ] Metrics.ast_cache_lookups;
      match Grammar.parse expression with
      | Ok ast ->
          Store.cache_put store expression ast;
          (Ok ast, false)
      | Error e -> (Error e, false))

(** Publishes a stored output and marks it published.

    {b Description:} Sends [output_event] keyed by [task_id] and, after the
    acknowledgement, sets the row to [published].

    {b Business Justification:} Shared by the first attempt and by retries of a
    [pending] event.

    {b Errors:} the publisher's failure (the row stays [pending]);
    {!Store.Error}.

    {b Side Effects:} one Kafka message; one update.

    {b Complexity:} O(1) plus the broker round trip.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      publish_stored ~store ~publish ~event_id ~task_id output_event
    ]}

    {b See Also:} {!handle}.

    @param store the parser database.
    @param publish the Kafka publisher.
    @param event_id the consumed event's identifier.
    @param task_id the task, used as the message key.
    @param output_event the serialized output event.
    @return a promise resolved once the row is marked.
    @since parser 0.1.0 *)
let publish_stored ~store ~(publish : publisher) ~event_id ~task_id output_event
    =
  Lwt.bind (publish ~key:task_id output_event) (fun () ->
      Store.mark_published store ~event_id;
      Lwt.return_unit)

(** Records a rejection and returns its outcome.

    {b Description:} Stores [code: message] as the reason and increments
    [parser_expressions_rejected_total{reason=code}].

    {b Business Justification:} A rejected task is explainable and is not
    evaluated twice.

    {b Errors:} {!Store.Error}.

    {b Side Effects:} one insert; one counter.

    {b Complexity:} O(1).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      reject ~store event "missing_operator" "no '+' operator"
    ]}

    {b See Also:} {!handle}.

    @param store the parser database.
    @param event the consumed event.
    @param code the rejection code.
    @param message the rejection description.
    @return the [Rejected] outcome.
    @raise Store.Error on a database failure.
    @since parser 0.1.0 *)
let reject ~store (event : Event.submitted) code message =
  (* TEMPORARY(P3.6): a rejection is only recorded; P3.6 reports it so that
     the saga marks the task FAILED. *)
  Store.record_rejected store ~event_id:event.event_id ~task_id:event.task_id
    ~reason:(code ^ ": " ^ message);
  Metrics.inc ~labels:[ ("reason", code) ] Metrics.expressions_rejected;
  Rejected { task_id = event.task_id; code; message }

(** Evaluates a decoded event that was not processed before.

    {b Description:} Parses the expression ({!parse_cached}), converts the
    operands ({!Operands.of_ast}), then stores and publishes the output.

    {b Business Justification:} The new-event branch of {!handle}.

    {b Errors:} {!Store.Error}; the publisher's failure.

    {b Side Effects:} database writes; one Kafka message unless rejected.

    {b Complexity:} O(n) in the length of the expression.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      evaluate ~store ~publish ~span ~now_ms event
    ]}

    {b See Also:} {!handle}.

    @param store the parser database.
    @param publish the Kafka publisher.
    @param span the context of the processing span.
    @param now_ms the time of the produced event.
    @param event the consumed event.
    @return the outcome.
    @since parser 0.1.0 *)
let evaluate ~store ~publish ~span ~now_ms (event : Event.submitted) =
  match parse_cached store event.expression with
  | Error e, _ ->
      Lwt.return
        (reject ~store event (Grammar.error_code e) (Grammar.error_message e))
  | Ok ast, cache_hit -> (
      match Operands.of_ast ast with
      | Error e ->
          Lwt.return
            (reject ~store event (Operands.error_code e)
               (Operands.error_message e))
      | Ok (a, b) ->
          let output_event =
            Yojson.Safe.to_string
              (Event.addition_requested ~now_ms ~task_id:event.task_id ~span ~a
                 ~b)
          in
          Store.record_pending store ~event_id:event.event_id
            ~task_id:event.task_id ~output_event;
          Lwt.map
            (fun () -> Published { task_id = event.task_id; a; b; cache_hit })
            (publish_stored ~store ~publish ~event_id:event.event_id
               ~task_id:event.task_id output_event))

(** Writes the log line of an outcome.

    {b Description:} [info] for published and duplicate events, [warn] for
    rejections, [error] for discarded messages.

    {b Business Justification:} Every consumed message leaves one log line with
    its task and trace.

    {b Errors:} None.

    {b Side Effects:} one log line.

    {b Complexity:} O(1).

    {b Thread Safety:} see {!Log}.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      log_outcome ~span (Duplicate { task_id = "t" })
    ]}

    {b See Also:} {!Log.emit}.

    @param span the context of the processing span.
    @param outcome the outcome.
    @since parser 0.1.0 *)
let log_outcome ~span = function
  | Published { task_id; a; b; cache_hit } ->
      Log.emit ~task_id ~trace:span
        ~fields:
          [ ("a", `Int a); ("b", `Int b); ("astCacheHit", `Bool cache_hit) ]
        Log.Info "addition requested"
  | Republished { task_id } ->
      Log.emit ~task_id ~trace:span Log.Info
        "addition requested (stored event republished)"
  | Duplicate { task_id } ->
      Log.emit ~task_id ~trace:span Log.Info "duplicate event ignored"
  | Rejected { task_id; code; message } ->
      Log.emit ~task_id ~trace:span
        ~fields:[ ("reason", `String code); ("detail", `String message) ]
        Log.Warn "expression rejected"
  | Discarded { reason } ->
      Log.emit ~trace:span
        ~fields:[ ("reason", `String reason) ]
        Log.Error "message discarded: not an aaas.expression.submitted.v1 event"

(** Processes one consumed message.

    {b Description:} See the module documentation for the steps. The outcome is
    logged and counted in [parser_events_consumed_total{outcome}].

    {b Business Justification:} The parser's role in the request flow (CLAUDE.md
    3, step 4).

    {b Errors:} {!Store.Error} on a database failure and the publisher's
    failure; in both cases nothing is counted and the caller retries the same
    message.

    {b Side Effects:} reads and writes the parser database; publishes at most
    one Kafka message; one log line; metrics.

    {b Complexity:} O(n) in the size of the message.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      handle ~store ~publish ~now_ms:(Timestamp.now_ms ()) raw
    ]}

    {b See Also:} {!Consumer}, {!Event.decode_submitted}.

    @param store the parser database.
    @param publish the Kafka publisher.
    @param now_ms the time of a produced event.
    @param raw the message value.
    @return the outcome.
    @since parser 0.1.0 *)
let handle ~store ~publish ~now_ms raw =
  let finish span outcome =
    log_outcome ~span outcome;
    Metrics.inc
      ~labels:[ ("outcome", outcome_label outcome) ]
      Metrics.events_consumed;
    Lwt.return outcome
  in
  match Event.decode_submitted raw with
  | Error reason ->
      (* TEMPORARY(P3.6): an undecodable message is only logged and counted;
         P3.6 sends it to aaas.dlq.v1. *)
      finish (Trace_context.child None) (Discarded { reason })
  | Ok event -> (
      let span = Trace_context.child event.traceparent in
      match Store.find_processed store event.event_id with
      | Some { status = Store.Published | Store.Rejected; _ } ->
          finish span (Duplicate { task_id = event.task_id })
      | Some { status = Store.Pending; output_event = Some output_event } ->
          Lwt.bind
            (publish_stored ~store ~publish ~event_id:event.event_id
               ~task_id:event.task_id output_event) (fun () ->
              finish span (Republished { task_id = event.task_id }))
      | Some { status = Store.Pending; output_event = None } ->
          raise
            (Store.Error ("pending event without output: " ^ event.event_id))
      | None ->
          Lwt.bind (evaluate ~store ~publish ~span ~now_ms event) (finish span))
