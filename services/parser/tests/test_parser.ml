(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Test_parser
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Unit tests of every module of the aaas_parser library,
                    including the processor against a real SQLite database
                    and contract fixtures from contracts/events/.
   Related Docs:    services/parser/README.md (Running and testing), ADR-0015
 *)

(** Unit tests of the parser.

    {b Description:} One Alcotest suite per module. The processor tests use a
    SQLite database file in a temporary directory and a fake publisher. Inputs
    are the valid examples of [aaas.expression.submitted.v1] from
    [CONTRACTS_DIR] (default [../../contracts], the repository layout). When
    [PRODUCED_DIR] is set, every event the processor publishes is written there,
    and the Dockerfile test stage validates those files against the JSON Schema
    of [aaas.addition.requested.v1] ([scripts/validate-events.py --events]).

    {b Business Justification:} [make test-parser] (CLAUDE.md 6.3).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

open Aaas_parser

(** Shorthand for an Alcotest case.

    {b Description:} A quick test named [name] running [f].

    {b Business Justification:} Keeps the suites compact.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let case name f = Alcotest.test_case name `Quick f

(** Alcotest checker of ASTs.

    {b Description:} Compares with structural equality and prints with
    {!Ast.to_string}.

    {b Business Justification:} Readable failures of grammar tests.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let ast_testable = Alcotest.testable (Fmt.of_to_string Ast.to_string) ( = )

(** Alcotest checker of parse results.

    {b Description:} [Ok] ASTs or [Error] codes of {!Grammar.error_code}.

    {b Business Justification:} Grammar tests compare whole results.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let parse_result =
  Alcotest.result ast_testable
    (Alcotest.testable (Fmt.of_to_string Grammar.error_message) ( = ))

(** Builds the AST of [a+b] from two digit strings.

    {b Description:} Uses {!Ast.numeral}, so leading zeros are removed.

    {b Business Justification:} Expected values of grammar tests.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let addition a b =
  Ast.Addition { augend = Ast.numeral a; addend = Ast.numeral b }

(** Tests of {!Ast}.

    {b Description:} Canonical numerals, rendering and the JSON round trip.

    {b Business Justification:} The cache format must stay readable.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let ast_tests =
  [
    case "numeral strips leading zeros" (fun () ->
        Alcotest.(check string) "007" "7" (Ast.numeral "007").digits;
        Alcotest.(check string) "000" "0" (Ast.numeral "000").digits;
        Alcotest.(check string) "0" "0" (Ast.numeral "0").digits;
        Alcotest.(check string) "100" "100" (Ast.numeral "100").digits);
    case "numeral rejects non-digits" (fun () ->
        List.iter
          (fun text ->
            match Ast.numeral text with
            | _ -> Alcotest.failf "accepted %S" text
            | exception Invalid_argument _ -> ())
          [ ""; "1a"; "+"; "-1"; " 1" ]);
    case "to_string" (fun () ->
        Alcotest.(check string)
          "canonical" "2+3"
          (Ast.to_string (addition "02" "3")));
    case "json form" (fun () ->
        Alcotest.(check string)
          "json"
          {|{"type":"addition","augend":{"type":"numeral","digits":"2"},"addend":{"type":"numeral","digits":"3"}}|}
          (Yojson.Safe.to_string (Ast.to_json (addition "2" "3"))));
    case "json round trip" (fun () ->
        let e = addition "99999" "0" in
        Alcotest.(check (result ast_testable string))
          "round trip" (Ok e)
          (Ast.of_json (Ast.to_json e)));
    case "of_json rejects other shapes" (fun () ->
        List.iter
          (fun json ->
            match Ast.of_json (Yojson.Safe.from_string json) with
            | Ok _ -> Alcotest.failf "accepted %s" json
            | Error _ -> ())
          [
            "[]";
            {|{"type":"subtraction"}|};
            {|{"type":"addition","augend":{"type":"numeral","digits":"x"},"addend":{"type":"numeral","digits":"1"}}|};
            {|{"type":"addition","augend":{"type":"numeral","digits":"1"}}|};
          ]);
  ]

(** Tests of {!Lexer}.

    {b Description:} Tokens, positions and lexical errors.

    {b Business Justification:} First stage of parsing.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let lexer_tests =
  [
    case "tokenize" (fun () ->
        match Lexer.tokenize "12+3" with
        | Ok
            [
              { token = Lexer.Number "12"; position = 1 };
              { token = Lexer.Plus; position = 3 };
              { token = Lexer.Number "3"; position = 4 };
            ] ->
            ()
        | _ -> Alcotest.fail "unexpected tokens");
    case "empty" (fun () ->
        Alcotest.(check bool) "no tokens" true (Lexer.tokenize "" = Ok []));
    case "invalid character" (fun () ->
        match Lexer.tokenize "2+3=" with
        | Error { character = '='; position = 4 } -> ()
        | _ -> Alcotest.fail "expected an error at position 4");
  ]

(** Tests of {!Grammar}.

    {b Description:} Every accepted shape and every rejection reason.

    {b Business Justification:} The core of the service.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let grammar_tests =
  let accepts text a b =
    case ("accepts " ^ text) (fun () ->
        Alcotest.check parse_result text
          (Ok (addition a b))
          (Grammar.parse text))
  in
  let rejects text error =
    case
      ("rejects " ^ if text = "" then "empty" else text)
      (fun () ->
        Alcotest.check parse_result text (Error error) (Grammar.parse text))
  in
  [
    accepts "2+3" "2" "3";
    accepts "0+0" "0" "0";
    accepts "9+1" "9" "1";
    accepts "007+3" "7" "3";
    accepts "99999+1" "99999" "1";
    accepts "99999+99999" "99999" "99999";
    accepts "123456789012345678901234567890+1" "123456789012345678901234567890"
      "1";
    rejects "" Grammar.Empty_expression;
    rejects "23" Grammar.Missing_operator;
    rejects "+3" Grammar.Missing_left_operand;
    rejects "+" Grammar.Missing_left_operand;
    rejects "2+" Grammar.Missing_right_operand;
    rejects "2++3" (Grammar.Unexpected_operator { position = 3 });
    rejects "1+2+3" (Grammar.Unexpected_operator { position = 4 });
    rejects "2+3+" (Grammar.Unexpected_operator { position = 4 });
    rejects "2+3=" (Grammar.Invalid_character { character = '='; position = 4 });
    rejects "a+1" (Grammar.Invalid_character { character = 'a'; position = 1 });
    case "error codes and messages" (fun () ->
        Alcotest.(check string)
          "code" "unexpected_operator"
          (Grammar.error_code (Grammar.Unexpected_operator { position = 3 }));
        Alcotest.(check string)
          "message"
          "unexpected '+' at position 3: exactly one operator is allowed"
          (Grammar.error_message (Grammar.Unexpected_operator { position = 3 }));
        List.iter
          (fun e ->
            Alcotest.(check bool)
              "non-empty" true
              (Grammar.error_message e <> ""))
          [
            Grammar.Empty_expression;
            Grammar.Invalid_character { character = 'x'; position = 1 };
            Grammar.Missing_operator;
            Grammar.Missing_left_operand;
            Grammar.Missing_right_operand;
          ]);
  ]

(** Tests of {!Operands}.

    {b Description:} Range bounds of the addition contract.

    {b Business Justification:} No event outside the schema is published.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let operands_tests =
  [
    case "in range" (fun () ->
        Alcotest.(check (result (pair int int) reject))
          "2+3"
          (Ok (2, 3))
          (Operands.of_ast (addition "2" "3"));
        Alcotest.(check (result (pair int int) reject))
          "max"
          (Ok (99999, 0))
          (Operands.of_ast (addition "99999" "0")));
    case "out of range" (fun () ->
        (match Operands.of_ast (addition "100000" "1") with
        | Error (Operands.Out_of_range { operand = "a"; digits = "100000" }) ->
            ()
        | _ -> Alcotest.fail "a above range");
        match
          Operands.of_ast (addition "1" "123456789012345678901234567890")
        with
        | Error (Operands.Out_of_range { operand = "b"; _ } as e) ->
            Alcotest.(check string)
              "shortened"
              "operand b = 12345678901234567890... is outside the range \
               0..99999"
              (Operands.error_message e);
            Alcotest.(check string)
              "code" "operand_out_of_range" (Operands.error_code e)
        | _ -> Alcotest.fail "b above range");
  ]

(** Lowercase UUIDv7 pattern check.

    {b Description:} 8-4-4-4-12 hex, version 7, variant [10].

    {b Business Justification:} Same rule as the envelope schema.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let is_uuid_v7 s =
  Event.is_uuid s && s.[14] = '7' && String.contains "89ab" s.[19]

(** Tests of {!Uuid_v7}, {!Entropy}, {!Timestamp} and {!Trace_context}.

    {b Description:} Identifier layouts and timestamp formatting.

    {b Business Justification:} Formats fixed by ADR-0013.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let identifier_tests =
  [
    case "uuid layout" (fun () ->
        Alcotest.(check string)
          "zero random" "018f3c2e-7b1a-7000-8000-000000000000"
          (Uuid_v7.of_parts ~unix_ms:0x018f3c2e7b1aL
             ~random:(Bytes.make 10 '\x00'));
        Alcotest.(check string)
          "all ones" "018f3c2e-7b1a-7fff-bfff-ffffffffffff"
          (Uuid_v7.of_parts ~unix_ms:0x018f3c2e7b1aL
             ~random:(Bytes.make 10 '\xff')));
    case "uuid generate" (fun () ->
        let a = Uuid_v7.generate () and b = Uuid_v7.generate () in
        Alcotest.(check bool) "v7" true (is_uuid_v7 a);
        Alcotest.(check bool) "unique" true (a <> b));
    case "entropy hex" (fun () ->
        Alcotest.(check string)
          "hex" "01ab"
          (Entropy.hex (Bytes.of_string "\x01\xab"));
        Alcotest.(check int) "length" 16 (Bytes.length (Entropy.bytes 16)));
    case "timestamp format" (fun () ->
        Alcotest.(check string)
          "example" "2026-10-16T12:00:00.000Z"
          (Timestamp.format 1_792_152_000_000L);
        Alcotest.(check string)
          "millis" "1970-01-01T00:00:00.007Z" (Timestamp.format 7L);
        Alcotest.(check string)
          "leap day" "2028-02-29T23:59:59.999Z"
          (Timestamp.format 1_835_481_599_999L);
        Alcotest.(check int) "now length" 24 (String.length (Timestamp.now ())));
    case "traceparent parse" (fun () ->
        (match
           Trace_context.parse
             "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
         with
        | Some
            {
              trace_id = "4bf92f3577b34da6a3ce929d0e0e4736";
              span_id = "00f067aa0ba902b7";
              flags = "01";
            } ->
            ()
        | _ -> Alcotest.fail "valid traceparent");
        List.iter
          (fun value ->
            Alcotest.(check bool) value true (Trace_context.parse value = None))
          [
            "";
            "01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";
            "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01";
            "00-00000000000000000000000000000000-00f067aa0ba902b7-01";
            "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01";
            "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7";
          ]);
    case "traceparent child" (fun () ->
        let parent =
          Trace_context.parse
            "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        in
        let child = Trace_context.child parent in
        Alcotest.(check string)
          "trace" "4bf92f3577b34da6a3ce929d0e0e4736" child.trace_id;
        Alcotest.(check bool)
          "new span" true
          (child.span_id <> "00f067aa0ba902b7");
        Alcotest.(check bool)
          "valid" true
          (Trace_context.parse (Trace_context.to_string child) = Some child);
        let root = Trace_context.child None in
        Alcotest.(check string) "sampled" "01" root.flags;
        Alcotest.(check bool)
          "valid root" true
          (Trace_context.parse (Trace_context.to_string root) = Some root));
  ]

(** Directory of the event contracts.

    {b Description:} [CONTRACTS_DIR] or the repository's [contracts/], relative
    to the test's working directory ([_build/default/tests]).

    {b Business Justification:} The valid examples are the test fixtures
    (ADR-0013).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let contracts_dir =
  match Sys.getenv_opt "CONTRACTS_DIR" with
  | Some dir -> dir
  | None -> "../../../../../contracts"

(** Reads a whole file.

    {b Description:} Binary mode.

    {b Business Justification:} Loads fixtures and migrations.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let read_file path = In_channel.with_open_bin path In_channel.input_all

(** The valid examples of [aaas.expression.submitted.v1].

    {b Description:} [(file name, contents)] pairs, sorted by name.

    {b Business Justification:} Contract fixtures of the consumer.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let submitted_examples () =
  let dir =
    Filename.concat contracts_dir
      "events/examples/aaas.expression.submitted.v1/valid"
  in
  Sys.readdir dir |> Array.to_list |> List.sort compare
  |> List.map (fun name -> (name, read_file (Filename.concat dir name)))

(** Builds an [aaas.expression.submitted.v1] message.

    {b Description:} The envelope of the [two-plus-three] example with the given
    identifiers and expression.

    {b Business Justification:} Processor tests need many variants.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let submitted ?(event_id = "018f3c2e-7b1a-7c3d-9f00-000000000010")
    ?(task_id = "018f3c2e-7b1a-7c3d-9f00-0000000000aa")
    ?(traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
    expression =
  Yojson.Safe.to_string
    (`Assoc
       [
         ("eventId", `String event_id);
         ("type", `String "aaas.expression.submitted");
         ("version", `Int 1);
         ("occurredAt", `String "2026-10-16T11:59:59.950Z");
         ("producer", `String "expression-assembler");
         ("taskId", `String task_id);
         ("traceparent", `String traceparent);
         ( "payload",
           `Assoc
             [
               ("sessionId", `String "5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90");
               ("expression", `String expression);
             ] );
       ])

(** Tests of {!Event}.

    {b Description:} Decoding of the contract examples and of broken messages;
    the shape of the produced event.

    {b Business Justification:} Contract conformance of both directions.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let event_tests =
  [
    case "decodes every valid contract example" (fun () ->
        let examples = submitted_examples () in
        Alcotest.(check bool) "fixtures found" true (examples <> []);
        List.iter
          (fun (name, raw) ->
            match Event.decode_submitted raw with
            | Ok e ->
                Alcotest.(check bool)
                  (name ^ " trace") true (e.traceparent <> None)
            | Error m -> Alcotest.failf "%s: %s" name m)
          examples);
    case "tolerates unknown fields and a missing traceparent" (fun () ->
        let raw =
          {|{"eventId":"018f3c2e-7b1a-7c3d-9f00-000000000010","type":"aaas.expression.submitted","version":1,"taskId":"018f3c2e-7b1a-7c3d-9f00-0000000000aa","payload":{"expression":"2+3","extra":1},"future":true}|}
        in
        match Event.decode_submitted raw with
        | Ok { expression = "2+3"; traceparent = None; _ } -> ()
        | _ -> Alcotest.fail "expected a tolerant decode");
    case "rejects broken messages" (fun () ->
        List.iter
          (fun (raw, expected) ->
            match Event.decode_submitted raw with
            | Ok _ -> Alcotest.failf "accepted %s" raw
            | Error m ->
                Alcotest.(check bool)
                  (raw ^ ": " ^ m)
                  true
                  (String.length m >= String.length expected
                  && String.sub m 0 (String.length expected) = expected))
          [
            ("{probe", "not JSON");
            ("[]", "not a JSON object");
            ({|{"probe":1}|}, "type:");
            ({|{"type":"aaas.expression.submitted","version":2}|}, "version:");
            ( {|{"type":"aaas.expression.submitted","version":1,"eventId":"X"}|},
              "eventId:" );
            ( {|{"type":"aaas.expression.submitted","version":1,"eventId":"018f3c2e-7b1a-7c3d-9f00-000000000010","taskId":null}|},
              "taskId:" );
            ( {|{"type":"aaas.expression.submitted","version":1,"eventId":"018f3c2e-7b1a-7c3d-9f00-000000000010","taskId":"018f3c2e-7b1a-7c3d-9f00-0000000000aa"}|},
              "payload:" );
            ( {|{"type":"aaas.expression.submitted","version":1,"eventId":"018f3c2e-7b1a-7c3d-9f00-000000000010","taskId":"018f3c2e-7b1a-7c3d-9f00-0000000000aa","payload":{}}|},
              "payload.expression:" );
          ]);
    case "addition_requested shape" (fun () ->
        let span = Trace_context.child None in
        let e =
          Event.addition_requested ~now_ms:1_792_152_000_000L
            ~task_id:"018f3c2e-7b1a-7c3d-9f00-0000000000aa" ~span ~a:3 ~b:2
        in
        let open Yojson.Safe.Util in
        Alcotest.(check (list string))
          "field order"
          [
            "eventId";
            "type";
            "version";
            "occurredAt";
            "producer";
            "taskId";
            "traceparent";
            "payload";
          ]
          (keys e);
        Alcotest.(check bool)
          "eventId" true
          (is_uuid_v7 (to_string (member "eventId" e)));
        Alcotest.(check string)
          "occurredAt" "2026-10-16T12:00:00.000Z"
          (to_string (member "occurredAt" e));
        Alcotest.(check string)
          "traceparent"
          (Trace_context.to_string span)
          (to_string (member "traceparent" e));
        Alcotest.(check string)
          "payload" {|{"a":3,"b":2}|}
          (Yojson.Safe.to_string (member "payload" e)));
  ]

(** Directory of the migrations.

    {b Description:} [MIGRATIONS_DIR] or the service's [migrations/] relative to
    [_build/default/tests].

    {b Business Justification:} The tests run the real migrations.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let migrations_dir =
  match Sys.getenv_opt "MIGRATIONS_DIR" with
  | Some dir -> dir
  | None -> "../../../migrations"

(** Opens a migrated database in a new temporary file.

    {b Description:} A file (not [:memory:]) so that WAL mode is exercised as in
    production.

    {b Business Justification:} Isolation between tests.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let fresh_store () =
  let path = Filename.temp_file "parser-test-" ".db" in
  Sys.remove path;
  let store = Store.open_db path in
  ignore (Store.migrate store ~dir:migrations_dir);
  (store, path)

(** Tests of {!Store}.

    {b Description:} Migrations, the AST cache and the processed-events
    lifecycle against a real SQLite file.

    {b Business Justification:} The database is the idempotency record.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let store_tests =
  [
    case "migrations apply once and survive reopening" (fun () ->
        let path = Filename.temp_file "parser-test-" ".db" in
        Sys.remove path;
        let store = Store.open_db path in
        Alcotest.(check int) "first" 1 (Store.migrate store ~dir:migrations_dir);
        Alcotest.(check int)
          "second" 0
          (Store.migrate store ~dir:migrations_dir);
        Store.close store;
        let store = Store.open_db path in
        Alcotest.(check int)
          "reopened" 0
          (Store.migrate store ~dir:migrations_dir);
        Alcotest.(check bool) "ping" true (Store.ping store);
        Store.close store);
    case "failed migration leaves nothing behind" (fun () ->
        let dir = Filename.temp_file "parser-migrations-" "" in
        Sys.remove dir;
        Sys.mkdir dir 0o755;
        Out_channel.with_open_bin (Filename.concat dir "0001_broken.sql")
          (fun oc ->
            output_string oc
              "CREATE TABLE half (x INTEGER); CREATE TABLE half (x INTEGER);");
        let store = Store.open_db ":memory:" in
        (match Store.migrate store ~dir with
        | _ -> Alcotest.fail "expected a failure"
        | exception Store.Error _ -> ());
        Alcotest.(check int)
          "rolled back" 0
          (List.length
             (Store.query store "check"
                "SELECT name FROM sqlite_schema WHERE name = 'half'" [])));
    case "ast cache" (fun () ->
        let store, _ = fresh_store () in
        Alcotest.(check bool) "miss" true (Store.cache_find store "2+3" = None);
        Store.cache_put store "2+3" (addition "2" "3");
        Store.cache_put store "2+3" (addition "2" "3");
        Alcotest.(check bool)
          "hit" true
          (Store.cache_find store "2+3" = Some (addition "2" "3"));
        ignore (Store.cache_find store "2+3");
        Alcotest.(check (list (array (option string))))
          "hits" [ [| Some "2" |] ]
          (Store.query store "hits"
             "SELECT hits FROM ast_cache WHERE expression = ?"
             [ `Text "2+3" ]));
    case "corrupt cache entry is a miss" (fun () ->
        let store, _ = fresh_store () in
        ignore
          (Store.query store "corrupt"
             "INSERT INTO ast_cache (expression, ast_json, created_at) VALUES \
              ('1+1', 'nope', 'x')"
             []);
        Alcotest.(check bool) "miss" true (Store.cache_find store "1+1" = None));
    case "processed events lifecycle" (fun () ->
        let store, _ = fresh_store () in
        let event_id = "018f3c2e-7b1a-7c3d-9f00-000000000010" in
        Alcotest.(check bool)
          "unknown" true
          (Store.find_processed store event_id = None);
        Store.record_pending store ~event_id ~task_id:"t" ~output_event:"{}";
        (match Store.find_processed store event_id with
        | Some { status = Store.Pending; output_event = Some "{}" } -> ()
        | _ -> Alcotest.fail "pending");
        (match
           Store.record_pending store ~event_id ~task_id:"t" ~output_event:"{}"
         with
        | () -> Alcotest.fail "duplicate accepted"
        | exception Store.Error _ -> ());
        Store.mark_published store ~event_id;
        (match Store.find_processed store event_id with
        | Some { status = Store.Published; output_event = Some "{}" } -> ()
        | _ -> Alcotest.fail "published");
        Store.record_rejected store ~event_id:"other" ~task_id:"t" ~reason:"r";
        match Store.find_processed store "other" with
        | Some { status = Store.Rejected; output_event = None } -> ()
        | _ -> Alcotest.fail "rejected");
  ]

(** Number of events written to [PRODUCED_DIR] so far.

    {b Description:} Gives every written file a unique name across tests.

    {b Business Justification:} Every published event is validated.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let produced_count = ref 0

(** A fake publisher recording messages.

    {b Description:} Returns the publisher and the list of [(key, value)]
    published so far; the first [fail_first] calls fail.

    {b Business Justification:} Processor tests without a broker.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let fake_publisher ?(fail_first = 0) () =
  let sent = ref [] and calls = ref 0 in
  let publish ~key value =
    incr calls;
    if !calls <= fail_first then Lwt.fail (Failure "broker down")
    else (
      sent := (key, value) :: !sent;
      (match Sys.getenv_opt "PRODUCED_DIR" with
      | Some dir ->
          incr produced_count;
          let name = Printf.sprintf "%03d-%s.json" !produced_count key in
          Out_channel.with_open_bin (Filename.concat dir name) (fun oc ->
              output_string oc value)
      | None -> ());
      Lwt.return_unit)
  in
  (publish, fun () -> List.rev !sent)

(** Runs {!Processor.handle} synchronously.

    {b Description:} [Lwt_main.run] around one call with a fixed clock.

    {b Business Justification:} Keeps the processor tests sequential.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let handle ~store ~publish raw =
  Lwt_main.run (Processor.handle ~store ~publish ~now_ms:1_792_152_000_000L raw)

(** Tests of {!Processor}.

    {b Description:} Every outcome, idempotency on redelivery and the
    republication of a pending output after a failed publish.

    {b Business Justification:} The behaviour CLAUDE.md 3 (step 4) and 4.2
    require.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let processor_tests =
  [
    case "every valid contract example" (fun () ->
        let store, _ = fresh_store () in
        let publish, sent = fake_publisher () in
        List.iter
          (fun (name, raw) ->
            match handle ~store ~publish raw with
            | Processor.Published _ | Processor.Rejected _ -> ()
            | o -> Alcotest.failf "%s: %s" name (Processor.outcome_label o))
          (submitted_examples ());
        Alcotest.(check bool) "published something" true (sent () <> []));
    case "publishes 2+3 keyed by task" (fun () ->
        let store, _ = fresh_store () in
        let publish, sent = fake_publisher () in
        (match handle ~store ~publish (submitted "2+3") with
        | Processor.Published { a = 2; b = 3; cache_hit = false; _ } -> ()
        | o -> Alcotest.failf "outcome %s" (Processor.outcome_label o));
        match sent () with
        | [ (key, value) ] ->
            Alcotest.(check string)
              "key" "018f3c2e-7b1a-7c3d-9f00-0000000000aa" key;
            let json = Yojson.Safe.from_string value in
            let open Yojson.Safe.Util in
            Alcotest.(check string)
              "payload" {|{"a":2,"b":3}|}
              (Yojson.Safe.to_string (member "payload" json));
            Alcotest.(check string)
              "trace continued" "4bf92f3577b34da6a3ce929d0e0e4736"
              (String.sub (to_string (member "traceparent" json)) 3 32)
        | _ -> Alcotest.fail "one message expected");
    case "redelivery is a duplicate" (fun () ->
        let store, _ = fresh_store () in
        let publish, sent = fake_publisher () in
        ignore (handle ~store ~publish (submitted "2+3"));
        (match handle ~store ~publish (submitted "2+3") with
        | Processor.Duplicate _ -> ()
        | o -> Alcotest.failf "outcome %s" (Processor.outcome_label o));
        Alcotest.(check int) "one message" 1 (List.length (sent ())));
    case "failed publish republishes the identical event" (fun () ->
        let store, _ = fresh_store () in
        let publish, sent = fake_publisher ~fail_first:1 () in
        (match handle ~store ~publish (submitted "2+3") with
        | _ -> Alcotest.fail "expected the publish failure to propagate"
        | exception Failure _ -> ());
        let stored =
          match
            Store.find_processed store "018f3c2e-7b1a-7c3d-9f00-000000000010"
          with
          | Some { status = Store.Pending; output_event = Some e } -> e
          | _ -> Alcotest.fail "pending row expected"
        in
        (match handle ~store ~publish (submitted "2+3") with
        | Processor.Republished _ -> ()
        | o -> Alcotest.failf "outcome %s" (Processor.outcome_label o));
        Alcotest.(check (list (pair string string)))
          "same event"
          [ ("018f3c2e-7b1a-7c3d-9f00-0000000000aa", stored) ]
          (sent ());
        match handle ~store ~publish (submitted "2+3") with
        | Processor.Duplicate _ -> ()
        | o -> Alcotest.failf "outcome %s" (Processor.outcome_label o));
    case "rejections are recorded and not published" (fun () ->
        let store, _ = fresh_store () in
        let publish, sent = fake_publisher () in
        List.iteri
          (fun i (expression, code) ->
            let event_id =
              Printf.sprintf "018f3c2e-7b1a-7c3d-9f00-0000000001%02d" i
            in
            match handle ~store ~publish (submitted ~event_id expression) with
            | Processor.Rejected { code = c; _ } ->
                Alcotest.(check string) expression code c
            | o ->
                Alcotest.failf "%s: %s" expression (Processor.outcome_label o))
          [
            ("2++3", "unexpected_operator");
            ("23", "missing_operator");
            ("+3", "missing_left_operand");
            ("2+", "missing_right_operand");
            ("100000+1", "operand_out_of_range");
          ];
        Alcotest.(check int) "nothing published" 0 (List.length (sent ()));
        match
          handle ~store ~publish
            (submitted ~event_id:"018f3c2e-7b1a-7c3d-9f00-000000000100" "2++3")
        with
        | Processor.Duplicate _ -> ()
        | o -> Alcotest.failf "outcome %s" (Processor.outcome_label o));
    case "repeated expression hits the cache" (fun () ->
        let store, _ = fresh_store () in
        let publish, _ = fake_publisher () in
        ignore (handle ~store ~publish (submitted "40+2"));
        match
          handle ~store ~publish
            (submitted ~event_id:"018f3c2e-7b1a-7c3d-9f00-000000000011"
               ~task_id:"018f3c2e-7b1a-7c3d-9f00-0000000000ab" "40+2")
        with
        | Processor.Published { cache_hit = true; a = 40; b = 2; _ } -> ()
        | o -> Alcotest.failf "outcome %s" (Processor.outcome_label o));
    case "broken messages are discarded" (fun () ->
        let store, _ = fresh_store () in
        let publish, sent = fake_publisher () in
        (match handle ~store ~publish {|{"probe":1}|} with
        | Processor.Discarded _ -> ()
        | o -> Alcotest.failf "outcome %s" (Processor.outcome_label o));
        Alcotest.(check int) "nothing published" 0 (List.length (sent ())));
    case "invalid traceparent starts a new trace" (fun () ->
        let store, _ = fresh_store () in
        let publish, sent = fake_publisher () in
        ignore (handle ~store ~publish (submitted ~traceparent:"garbage" "1+1"));
        match sent () with
        | [ (_, value) ] ->
            let open Yojson.Safe.Util in
            let tp =
              to_string (member "traceparent" (Yojson.Safe.from_string value))
            in
            Alcotest.(check bool) "valid" true (Trace_context.parse tp <> None)
        | _ -> Alcotest.fail "one message expected");
  ]

(** Tests of {!Config}.

    {b Description:} Defaults, overrides and every configuration error.

    {b Business Justification:} A misconfiguration stops the process.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let config_tests =
  let env pairs name = List.assoc_opt name pairs in
  [
    case "defaults" (fun () ->
        match Config.load (env []) with
        | Ok c ->
            Alcotest.(check string) "brokers" "redpanda:9092" c.brokers;
            Alcotest.(check int) "port" 8080 c.http_port;
            Alcotest.(check string) "db" "/data/parser.db" c.db_path;
            Alcotest.(check string) "group" "parser" c.consumer_group;
            Alcotest.(check int) "kafka log level" 0 c.kafka_log_level
        | Error m -> Alcotest.fail m);
    case "overrides" (fun () ->
        match
          Config.load
            (env
               [
                 ("AAAS_HTTP_PORT", "9000");
                 ("AAAS_KAFKA_BROKERS", "b:1");
                 ("AAAS_LOG_LEVEL", "DEBUG");
                 ("AAAS_DB_PATH", "");
               ])
        with
        | Ok c ->
            Alcotest.(check int) "port" 9000 c.http_port;
            Alcotest.(check string) "brokers" "b:1" c.brokers;
            Alcotest.(check bool) "level" true (c.log_level = Log.Debug);
            Alcotest.(check string)
              "empty means default" "/data/parser.db" c.db_path
        | Error m -> Alcotest.fail m);
    case "errors" (fun () ->
        List.iter
          (fun pairs ->
            match Config.load (env pairs) with
            | Ok _ -> Alcotest.fail "accepted"
            | Error _ -> ())
          [
            [ ("AAAS_BOOTSTRAP", "platform") ];
            [ ("AAAS_BOOTSTRAP", "magic") ];
            [ ("AAAS_HTTP_PORT", "http") ];
            [ ("AAAS_HTTP_PORT", "70000") ];
            [ ("AAAS_LOG_LEVEL", "loud") ];
            [ ("AAAS_KAFKA_LOG_LEVEL", "8") ];
            [ ("AAAS_KAFKA_LOG_LEVEL", "debug") ];
          ]);
  ]

(** Tests whether [needle] occurs in [haystack].

    {b Description:} Naive substring search.

    {b Business Justification:} Checks of the metrics text.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let contains haystack needle =
  let n = String.length needle and h = String.length haystack in
  let rec at i =
    i + n <= h && (String.sub haystack i n = needle || at (i + 1))
  in
  at 0

(** Tests of {!Log}, {!Metrics} and {!Http}.

    {b Description:} Log line fields, the metrics exposition and the routes.

    {b Business Justification:} Operational contract of CLAUDE.md 6.1.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let operations_tests =
  [
    case "log line fields" (fun () ->
        let trace = Trace_context.child None in
        let line =
          Log.line ~task_id:"t" ~trace ~fields:[ ("a", `Int 1) ] Log.Warn "m"
        in
        let open Yojson.Safe.Util in
        Alcotest.(check (list string))
          "keys"
          [
            "ts"; "level"; "service"; "msg"; "taskId"; "traceId"; "spanId"; "a";
          ]
          (keys line);
        Alcotest.(check string) "level" "warn" (to_string (member "level" line));
        Alcotest.(check string)
          "trace" trace.trace_id
          (to_string (member "traceId" line));
        Alcotest.(check bool)
          "levels" true
          (List.for_all
             (fun l -> Log.level_of_string (Log.level_name l) = Some l)
             [ Log.Debug; Log.Info; Log.Warn; Log.Error; Log.Fatal ]));
    case "log level filter" (fun () ->
        let lines = ref [] in
        let saved = !Log.sink in
        (Log.sink := fun l -> lines := l :: !lines);
        Log.min_level := Log.Warn;
        Log.emit Log.Info "dropped";
        Log.emit Log.Error "kept";
        Log.sink := saved;
        Log.min_level := Log.Info;
        Alcotest.(check int) "one line" 1 (List.length !lines));
    case "metrics exposition" (fun () ->
        let c = Metrics.counter "parser_test_total" "Test \"counter\"." in
        Metrics.inc c;
        Metrics.inc ~labels:[ ("k", "a\"b") ] c;
        Alcotest.(check (float 0.))
          "value" 1.
          (Metrics.value ~labels:[ ("k", "a\"b") ] c);
        let text = Metrics.render ~version:"0.1.0" in
        List.iter
          (fun expected ->
            Alcotest.(check bool) expected true (contains text expected))
          [
            "# TYPE parser_test_total counter\n";
            "parser_test_total 1\n";
            "parser_test_total{k=\"a\\\"b\"} 1\n";
            "parser_up 1\n";
            "parser_build_info{version=\"0.1.0\"} 1\n";
            "# TYPE parser_events_consumed_total counter\n";
          ]);
    case "health and routes" (fun () ->
        let run meth path checks =
          Lwt_main.run (Http.routes ~checks ~version:"0.1.0" ~meth ~path)
        in
        let ok = ("database", fun () -> Lwt.return true) in
        let bad = ("broker", fun () -> Lwt.fail (Failure "down")) in
        let r = run `GET "/health" [ ok ] in
        Alcotest.(check int) "200" 200 r.status;
        Alcotest.(check string)
          "body" {|{"status":"ok","checks":{"database":"ok"}}|} r.body;
        let r = run `GET "/health" [ ok; bad ] in
        Alcotest.(check int) "503" 503 r.status;
        Alcotest.(check string)
          "body"
          {|{"status":"error","checks":{"database":"ok","broker":"error"}}|}
          r.body;
        let r = run `GET "/metrics" [] in
        Alcotest.(check string)
          "type" "text/plain; version=0.0.4; charset=utf-8" r.content_type;
        let r = run `POST "/health" [] in
        Alcotest.(check int) "405" 405 r.status;
        Alcotest.(check string)
          "problem" "application/problem+json" r.content_type;
        let r = run `GET "/nope" [] in
        Alcotest.(check int) "404" 404 r.status);
    case "backoff has jitter within bounds" (fun () ->
        for attempt = 1 to 3 do
          let base = 0.2 *. (2. ** float_of_int (attempt - 1)) in
          let b = Consumer.backoff attempt in
          Alcotest.(check bool)
            "bounds" true
            (b >= base *. 0.5 && b <= base *. 1.5)
        done);
  ]

(** Runs every suite.

    {b Description:} Alcotest entry point.

    {b Business Justification:} [dune test].

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let () =
  (Log.sink := fun _ -> ());
  Alcotest.run "parser"
    [
      ("ast", ast_tests);
      ("lexer", lexer_tests);
      ("grammar", grammar_tests);
      ("operands", operands_tests);
      ("identifiers", identifier_tests);
      ("event", event_tests);
      ("store", store_tests);
      ("processor", processor_tests);
      ("config", config_tests);
      ("operations", operations_tests);
    ]
