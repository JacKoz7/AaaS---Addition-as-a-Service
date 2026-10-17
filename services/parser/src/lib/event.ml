(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Event
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Reads consumed aaas.expression.submitted.v1 events and
                    builds the aaas.addition.requested.v1 events the parser
                    publishes.
   Related Docs:    contracts/events/aaas.expression.submitted.v1.schema.json,
                    contracts/events/aaas.addition.requested.v1.schema.json,
                    CLAUDE.md 4.2, ADR-0013, ADR-0015
 *)

(** Event envelopes of the parser.

    {b Description:} The consumer is a tolerant reader (ADR-0013): it reads the
    fields it needs ([eventId], [type], [version], [taskId], [traceparent],
    [payload.expression]) and ignores unknown ones. The produced event follows
    the closed schema of [aaas.addition.requested.v1] exactly.

    {b Business Justification:} The parser's only inputs and outputs are events
    (CLAUDE.md 3, step 4).

    {b Thread Safety:} pure functions, except {!addition_requested}, which draws
    identifiers (see {!Entropy}).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** Topic consumed by the parser.

    {b Description:} [aaas.expression.submitted.v1].

    {b Business Justification:} CLAUDE.md 4.2, topic table.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let input_topic = "aaas.expression.submitted.v1"

(** Topic produced by the parser.

    {b Description:} [aaas.addition.requested.v1], keyed by [taskId].

    {b Business Justification:} CLAUDE.md 4.2, topic table.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let output_topic = "aaas.addition.requested.v1"

(** A consumed [aaas.expression.submitted.v1] event.

    {b Description:} The fields the parser uses. [traceparent] is [None] if the
    field is absent or invalid.

    {b Business Justification:} Input of {!Processor.handle}.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type submitted = {
  event_id : string;
  task_id : string;
  traceparent : Trace_context.t option;
  expression : string;
}

(** Tests whether a string is a lowercase canonical UUID.

    {b Description:} 8-4-4-4-12 lowercase hexadecimal digits of any version. The
    version is not checked: the consumer only needs a stable key, and the
    producer's schema guarantees UUIDv7.

    {b Business Justification:} [eventId] is the primary key of
    [processed_events] and [taskId] the key of the produced event; anything else
    is a malformed event.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      is_uuid "018f3c2e-7b1a-7c3d-9f00-000000000010" = true
    ]}

    {b See Also:} {!decode_submitted}.

    @param s the candidate.
    @return [true] for a lowercase canonical UUID.
    @since parser 0.1.0 *)
let is_uuid s =
  match String.split_on_char '-' s with
  | [ a; b; c; d; e ] ->
      Trace_context.is_hex 8 a && Trace_context.is_hex 4 b
      && Trace_context.is_hex 4 c && Trace_context.is_hex 4 d
      && Trace_context.is_hex 12 e
  | _ -> false

(** Monadic bind of [result], for the field checks of {!decode_submitted}.

    {b Description:} [let* x = r in f x] is [Result.bind r f].

    {b Business Justification:} Reads the checks of a decoder in order, stopping
    at the first failure.

    {b Errors:} None of its own; returns the first [Error].

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      (let* x = Ok 1 in
       Ok (x + 1))
      = Ok 2
    ]}

    {b See Also:} {!decode_submitted}.

    @param r a result.
    @param f the continuation.
    @return [f x] for [Ok x], otherwise [r]'s error.
    @since parser 0.1.0 *)
let ( let* ) = Result.bind

(** Reads a required UUID string field of a JSON object.

    {b Description:} The field must be a string accepted by {!is_uuid}.

    {b Business Justification:} [eventId] and [taskId] of the consumed event.

    {b Errors:} [Error "<name>: expected a lowercase UUID"].

    {b Side Effects:} None.

    {b Complexity:} O(n) in the number of fields.

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      uuid_field "taskId" [] = Error "taskId: expected a lowercase UUID"
    ]}

    {b See Also:} {!decode_submitted}.

    @param name the field name.
    @param fields the members of the object.
    @return the UUID.
    @since parser 0.1.0 *)
let uuid_field name fields =
  match List.assoc_opt name fields with
  | Some (`String s) when is_uuid s -> Ok s
  | _ -> Error (name ^ ": expected a lowercase UUID")

(** Decodes a consumed message.

    {b Description:} Parses [raw] as JSON and checks, in this order, the fields
    the parser relies on: [type = "aaas.expression.submitted"], [version = 1],
    UUID [eventId] and [taskId], an object [payload] and a string
    [payload.expression]. Unknown fields are ignored. The expression itself is
    not checked here: a malformed expression is a valid event that
    {!Grammar.parse} rejects. An absent or invalid [traceparent] is tolerated
    ([None]); a new trace is then started.

    {b Business Justification:} A message that is not such an event cannot be
    processed at all and is discarded (see {!Processor}).

    {b Errors:} [Error message] naming the first missing or wrong field, or the
    JSON syntax error.

    {b Side Effects:} None.

    {b Complexity:} O(n) time and memory in the size of [raw].

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      decode_submitted "{}"
      = Error "type: expected \"aaas.expression.submitted\""
    ]}

    {b See Also:} {!submitted}.

    @param raw the Kafka message value.
    @return the decoded event or the reason it is not one.
    @since parser 0.1.0 *)
let decode_submitted raw =
  match Yojson.Safe.from_string raw with
  | exception Yojson.Json_error message -> Error ("not JSON: " ^ message)
  | `Assoc fields ->
      let* () =
        match List.assoc_opt "type" fields with
        | Some (`String "aaas.expression.submitted") -> Ok ()
        | _ -> Error "type: expected \"aaas.expression.submitted\""
      in
      let* () =
        match List.assoc_opt "version" fields with
        | Some (`Int 1) -> Ok ()
        | _ -> Error "version: expected 1"
      in
      let* event_id = uuid_field "eventId" fields in
      let* task_id = uuid_field "taskId" fields in
      let* payload =
        match List.assoc_opt "payload" fields with
        | Some (`Assoc payload) -> Ok payload
        | _ -> Error "payload: expected an object"
      in
      let* expression =
        match List.assoc_opt "expression" payload with
        | Some (`String expression) -> Ok expression
        | _ -> Error "payload.expression: expected a string"
      in
      let traceparent =
        match List.assoc_opt "traceparent" fields with
        | Some (`String value) -> Trace_context.parse value
        | _ -> None
      in
      Ok { event_id; task_id; traceparent; expression }
  | _ -> Error "not a JSON object"

(** Builds the [aaas.addition.requested.v1] event of a parsed addition.

    {b Description:} Envelope with a new UUIDv7 [eventId], [occurredAt] at
    [now_ms], [producer = "parser"], the consumed [taskId], the traceparent of
    the processing span ([span]) and the payload [{a, b}]. Field order follows
    CLAUDE.md 4.2.

    {b Business Justification:} Hands the addition over to the computation (the
    ledger until P3.4, then saga-orchestrator).

    {b Errors:} [Sys_error] from {!Uuid_v7.generate}.

    {b Side Effects:} draws an identifier from the random source.

    {b Complexity:} O(1).

    {b Thread Safety:} see {!Entropy}.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      let span = Trace_context.child None in
      let e = addition_requested ~now_ms:0L ~task_id:"t" ~span ~a:2 ~b:3 in
      Yojson.Safe.Util.member "producer" e = `String "parser"
    ]}

    {b See Also:} {!output_topic}, {!Processor.handle}.

    @param now_ms the event time in milliseconds since the epoch.
    @param task_id the task of the consumed event.
    @param span the context of the processing span.
    @param a first operand, [0..99 999].
    @param b second operand, [0..99 999].
    @return the event as JSON.
    @since parser 0.1.0 *)
let addition_requested ~now_ms ~task_id ~span ~a ~b =
  `Assoc
    [
      ("eventId", `String (Uuid_v7.generate ()));
      ("type", `String "aaas.addition.requested");
      ("version", `Int 1);
      ("occurredAt", `String (Timestamp.format now_ms));
      ("producer", `String "parser");
      ("taskId", `String task_id);
      ("traceparent", `String (Trace_context.to_string span));
      ("payload", `Assoc [ ("a", `Int a); ("b", `Int b) ]);
    ]
