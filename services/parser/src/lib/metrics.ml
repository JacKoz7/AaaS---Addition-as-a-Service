(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Metrics
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Prometheus counters of the parser and their text
                    exposition for GET /metrics.
   Related Docs:    services/parser/docs/API.md, services/parser/docs/SLO.md,
                    CLAUDE.md 6.1, ADR-0015
 *)

(** Prometheus metrics.

    {b Description:} Counters with optional labels, kept in memory and rendered
    in the Prometheus text exposition format 0.0.4. Every metric name starts
    with [parser_] (CLAUDE.md 2: the service name is the metric prefix). The
    metrics are:
    - [parser_events_consumed_total{outcome}]: consumed messages by outcome
      ([published], [republished], [duplicate], [rejected], [discarded]);
    - [parser_expressions_rejected_total{reason}]: rejections by code;
    - [parser_ast_cache_lookups_total{result}]: [hit] or [miss];
    - [parser_publish_failures_total]: failed publication attempts;
    - [parser_processing_failures_total]: failed processing attempts (database
      or broker), each followed by a retry;
    - [parser_up]: always 1 while the process serves metrics;
    - [parser_build_info{version}]: always 1.

    {b Business Justification:} The SLO of the parser (SLO.md) is measured from
    these counters.

    {b Thread Safety:} one Lwt thread; not for concurrent system threads.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** A counter with labels.

    {b Description:} [values] maps the rendered label set (for example
    [outcome="published"]) to the count.

    {b Business Justification:} The only metric type the parser needs.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type counter = {
  name : string;
  help : string;
  values : (string, float) Hashtbl.t;
}

(** All registered counters, in registration order (reversed).

    {b Description:} Filled by {!val-counter}.

    {b Business Justification:} {!render} lists every metric.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let registry : counter list ref = ref []

(** Registers a counter.

    {b Description:} Creates the counter and adds it to {!registry}.

    {b Business Justification:} Declares the metrics of the module
    documentation.

    {b Errors:} None.

    {b Side Effects:} adds to {!registry}.

    {b Complexity:} O(1).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      let c = counter "parser_example_total" "Example." in
      c.name = "parser_example_total"
    ]}

    {b See Also:} {!inc}.

    @param name the metric name.
    @param help its description.
    @return the counter.
    @since parser 0.1.0 *)
let counter name help =
  let c = { name; help; values = Hashtbl.create 8 } in
  registry := c :: !registry;
  c

(** Escapes a label value for the text format.

    {b Description:} Backslash, double quote and newline are escaped.

    {b Business Justification:} Label values come from code paths that could, in
    future, carry user text.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(n).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      escape "a\"b" = "a\\\"b"
    ]}

    {b See Also:} {!render_labels}.

    @param s a label value.
    @return the escaped value.
    @since parser 0.1.0 *)
let escape s =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '\\' -> Buffer.add_string b "\\\\"
      | '"' -> Buffer.add_string b "\\\""
      | '\n' -> Buffer.add_string b "\\n"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

(** Renders a label set.

    {b Description:} [name="value"] pairs joined by commas, in the given order.

    {b Business Justification:} The key of a counter's values.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(n).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      render_labels [ ("outcome", "published") ] = "outcome=\"published\""
    ]}

    {b See Also:} {!inc}.

    @param pairs label names and values.
    @return the rendered set.
    @since parser 0.1.0 *)
let render_labels pairs =
  String.concat ","
    (List.map (fun (k, v) -> Printf.sprintf "%s=\"%s\"" k (escape v)) pairs)

(** Increments a counter.

    {b Description:} Adds 1 to the value of the label set.

    {b Business Justification:} Records one occurrence.

    {b Errors:} None.

    {b Side Effects:} changes the counter.

    {b Complexity:} O(1) expected.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      inc ~labels:[ ("outcome", "published") ] events_consumed
    ]}

    {b See Also:} {!value}.

    @param labels the label set (none by default).
    @param c the counter.
    @since parser 0.1.0 *)
let inc ?(labels = []) c =
  let key = render_labels labels in
  let current = Option.value ~default:0. (Hashtbl.find_opt c.values key) in
  Hashtbl.replace c.values key (current +. 1.)

(** Reads the value of a counter.

    {b Description:} 0 for a label set never incremented.

    {b Business Justification:} Tests and operational checks.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1) expected.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      value ~labels:[ ("outcome", "published") ] events_consumed >= 0.
    ]}

    {b See Also:} {!inc}.

    @param labels the label set (none by default).
    @param c the counter.
    @return the count.
    @since parser 0.1.0 *)
let value ?(labels = []) c =
  Option.value ~default:0. (Hashtbl.find_opt c.values (render_labels labels))

(** Consumed messages by outcome.

    {b Description:} [parser_events_consumed_total{outcome}], see the module
    documentation for the outcomes.

    {b Business Justification:} Throughput and correctness of the consumer
    (SLO.md).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let events_consumed =
  counter "parser_events_consumed_total"
    "Consumed aaas.expression.submitted.v1 messages by outcome."

(** Rejected expressions by reason.

    {b Description:} [parser_expressions_rejected_total{reason}], the reason
    being a {!Grammar.error_code} or {!Operands.error_code}.

    {b Business Justification:} Shows which typing mistakes users make.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let expressions_rejected =
  counter "parser_expressions_rejected_total"
    "Expressions that are not a valid addition, by reason."

(** AST cache lookups by result.

    {b Description:} [parser_ast_cache_lookups_total{result}], [hit] or [miss].

    {b Business Justification:} Effectiveness of the AST cache (CLAUDE.md 2).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let ast_cache_lookups =
  counter "parser_ast_cache_lookups_total" "AST cache lookups by result."

(** Failed publication attempts.

    {b Description:} [parser_publish_failures_total]: an
    [aaas.addition.requested.v1] message not acknowledged in time.

    {b Business Justification:} Broker trouble shows here before tasks stall
    (RUNBOOK.md).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let publish_failures =
  counter "parser_publish_failures_total"
    "Publication attempts of aaas.addition.requested.v1 that failed."

(** Failed processing attempts.

    {b Description:} [parser_processing_failures_total]: an attempt to process a
    message ended with a database or broker error and will be retried.

    {b Business Justification:} Alerting on a stuck consumer (RUNBOOK.md).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let processing_failures =
  counter "parser_processing_failures_total"
    "Attempts to process a message that failed and were retried."

(** Renders every metric in the Prometheus text format.

    {b Description:} [# HELP] and [# TYPE] lines and one sample per label set
    for every counter in registration order, then [parser_up 1] and
    [parser_build_info{version="..."} 1].

    {b Business Justification:} The body of [GET /metrics] (CLAUDE.md 6.1).

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(s) in the number of samples.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      String.length (render ~version:"0.1.0") > 0
    ]}

    {b See Also:} {!Http.routes}.

    @param version the service version for [parser_build_info].
    @return the exposition text.
    @since parser 0.1.0 *)
let render ~version =
  let b = Buffer.create 1024 in
  List.iter
    (fun c ->
      Printf.bprintf b "# HELP %s %s\n# TYPE %s counter\n" c.name c.help c.name;
      Hashtbl.fold (fun key v acc -> (key, v) :: acc) c.values []
      |> List.sort compare
      |> List.iter (fun (key, v) ->
          if key = "" then Printf.bprintf b "%s %.0f\n" c.name v
          else Printf.bprintf b "%s{%s} %.0f\n" c.name key v))
    (List.rev !registry);
  Printf.bprintf b
    "# HELP parser_up Whether the parser process is running.\n\
     # TYPE parser_up gauge\n\
     parser_up 1\n\
     # HELP parser_build_info Version of the running parser.\n\
     # TYPE parser_build_info gauge\n\
     parser_build_info{version=\"%s\"} 1\n"
    (escape version);
  Buffer.contents b
