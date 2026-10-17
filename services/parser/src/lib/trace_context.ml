(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Trace_context
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Reads the W3C traceparent of a consumed event and derives
                    the traceparent of the event produced for it.
   Related Docs:    W3C Trace Context, CLAUDE.md 6.1 (OpenTelemetry),
                    ADR-0013, ADR-0015
 *)

(** W3C Trace Context (version [00]).

    {b Description:} A traceparent is
    [00-<32 hex trace-id>-<16 hex parent-id>-<2 hex flags>], lowercase, with
    non-zero identifiers. Processing an event is one span: its trace identifier
    is the consumed event's, its parent is the consumed event's span, and its
    own span identifier is new. The produced event carries this span as its
    traceparent, so the trace continues across Redpanda.

    {b Business Justification:} "One trace per addition" (P7.2) requires every
    service to continue the trace it received (CLAUDE.md 6.1).

    {b Thread Safety:} see {!Entropy}.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** A parsed traceparent.

    {b Description:} [trace_id] (32 hex), [span_id] (16 hex) and [flags] (2
    hex), all lowercase.

    {b Business Justification:} Fields of the log lines ([traceId], [spanId])
    and of the produced event.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type t = { trace_id : string; span_id : string; flags : string }

(** Tests whether a string is lowercase hexadecimal of a given length.

    {b Description:} Only [0-9a-f]; uppercase is rejected as in the event
    schemas.

    {b Business Justification:} Validation of the traceparent fields.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(n).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      is_hex 2 "0a" = true && is_hex 2 "0A" = false
    ]}

    {b See Also:} {!parse}.

    @param length the required length.
    @param s the candidate.
    @return [true] if [s] has [length] lowercase hexadecimal characters.
    @since parser 0.1.0 *)
let is_hex length s =
  String.length s = length
  && String.for_all
       (fun c -> (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
       s

(** Tests whether a hexadecimal string is all zeros.

    {b Description:} W3C Trace Context forbids all-zero identifiers.

    {b Business Justification:} Validation of the traceparent fields.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(n).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      all_zero "0000" = true
    ]}

    {b See Also:} {!parse}.

    @param s a hexadecimal string.
    @return [true] if every character is ['0'].
    @since parser 0.1.0 *)
let all_zero s = String.for_all (fun c -> c = '0') s

(** Parses a traceparent header value.

    {b Description:} Accepts version [00] only, lowercase, with non-zero trace
    and parent identifiers, exactly as the envelope schema does.

    {b Business Justification:} The consumed event's trace is continued only if
    it is valid; otherwise a new trace starts ({!child}).

    {b Errors:} [None] for any other input.

    {b Side Effects:} None.

    {b Complexity:} O(1) (fixed length).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      parse "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
      = Some
          {
            trace_id = "4bf92f3577b34da6a3ce929d0e0e4736";
            span_id = "00f067aa0ba902b7";
            flags = "01";
          }
    ]}

    {b See Also:} {!to_string}.

    @param value the traceparent text.
    @return the parsed context, or [None] if invalid.
    @since parser 0.1.0 *)
let parse value =
  match String.split_on_char '-' value with
  | [ "00"; trace_id; span_id; flags ]
    when is_hex 32 trace_id && is_hex 16 span_id && is_hex 2 flags
         && (not (all_zero trace_id))
         && not (all_zero span_id) ->
      Some { trace_id; span_id; flags }
  | _ -> None

(** Renders a context as a traceparent value.

    {b Description:} [00-<trace_id>-<span_id>-<flags>].

    {b Business Justification:} The [traceparent] field of produced events.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      to_string
        {
          trace_id = String.make 32 'a';
          span_id = String.make 16 'b';
          flags = "01";
        }
      = "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01"
    ]}

    {b See Also:} {!parse}.

    @param t the context.
    @return the traceparent text.
    @since parser 0.1.0 *)
let to_string t = String.concat "-" [ "00"; t.trace_id; t.span_id; t.flags ]

(** Returns [n] random bytes as hexadecimal, never all zeros.

    {b Description:} Draws again in the (probability 2{^ -64} or less) case of
    an all-zero result.

    {b Business Justification:} New trace and span identifiers.

    {b Errors:} [Sys_error] from {!Entropy.bytes}.

    {b Side Effects:} reads the random source.

    {b Complexity:} O(n) expected.

    {b Thread Safety:} see {!Entropy}.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      String.length (random_id 8) = 16
    ]}

    {b See Also:} {!child}.

    @param n number of random bytes.
    @return [2 * n] hexadecimal characters.
    @since parser 0.1.0 *)
let rec random_id n =
  let id = Entropy.hex (Entropy.bytes n) in
  if all_zero id then random_id n else id

(** Derives the context of the span that processes an event.

    {b Description:} With a valid parent, keeps its trace identifier and flags
    and draws a new span identifier. Without one (absent or invalid
    traceparent), starts a new sampled trace ([flags = "01"]).

    {b Business Justification:} Continues the trace of the addition across the
    parser.

    {b Errors:} [Sys_error] from {!Entropy.bytes}.

    {b Side Effects:} reads the random source.

    {b Complexity:} O(1).

    {b Thread Safety:} see {!Entropy}.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      let parent =
        parse "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
      in
      (child parent).trace_id = "4bf92f3577b34da6a3ce929d0e0e4736"
    ]}

    {b See Also:} {!parse}, {!Event.addition_requested}.

    @param parent the consumed event's context, if valid.
    @return the context of the processing span.
    @since parser 0.1.0 *)
let child parent =
  match parent with
  | Some p -> { p with span_id = random_id 8 }
  | None -> { trace_id = random_id 16; span_id = random_id 8; flags = "01" }
