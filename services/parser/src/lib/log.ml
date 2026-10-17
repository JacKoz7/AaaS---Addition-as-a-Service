(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Log
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Structured JSON log lines on stdout with the fields of
                    CLAUDE.md 6.1.
   Related Docs:    CLAUDE.md 6.1, ADR-0015
 *)

(** Structured logging.

    {b Description:} One JSON object per line on stdout with [ts], [level],
    [service], [msg], [taskId], [traceId] and [spanId] (null when not known),
    followed by any extra fields. Levels: [debug], [info], [warn], [error],
    [fatal]; lines below the configured level are dropped.

    {b Business Justification:} Every service logs the same fields so that Loki
    (P7.1) can follow one task across 28 languages.

    {b Thread Safety:} writes are not interleaved within one system thread; the
    service runs one.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** Severity of a log line.

    {b Description:} Ordered from [Debug] (lowest) to [Fatal].

    {b Business Justification:} The level vocabulary shared by every AaaS
    service (debug, info, warn, error, fatal).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type level = Debug | Info | Warn | Error | Fatal

(** Numeric rank of a level, for filtering.

    {b Description:} [Debug] is 0, [Fatal] is 4.

    {b Business Justification:} Compares a line with the minimum level.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      rank Warn = 2
    ]}

    {b See Also:} {!emit}.

    @param level a level.
    @return its rank.
    @since parser 0.1.0 *)
let rank = function
  | Debug -> 0
  | Info -> 1
  | Warn -> 2
  | Error -> 3
  | Fatal -> 4

(** Name of a level in log lines.

    {b Description:} Lowercase: [debug], [info], [warn], [error], [fatal].

    {b Business Justification:} The shared level vocabulary.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      level_name Warn = "warn"
    ]}

    {b See Also:} {!level_of_string}.

    @param level a level.
    @return its name.
    @since parser 0.1.0 *)
let level_name = function
  | Debug -> "debug"
  | Info -> "info"
  | Warn -> "warn"
  | Error -> "error"
  | Fatal -> "fatal"

(** Reads a level name.

    {b Description:} The inverse of {!level_name}, case-insensitive.

    {b Business Justification:} The [AAAS_LOG_LEVEL] variable.

    {b Errors:} [None] for an unknown name.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      level_of_string "WARN" = Some Warn
    ]}

    {b See Also:} {!Config}.

    @param s a level name.
    @return the level, if known.
    @since parser 0.1.0 *)
let level_of_string s =
  match String.lowercase_ascii s with
  | "debug" -> Some Debug
  | "info" -> Some Info
  | "warn" -> Some Warn
  | "error" -> Some Error
  | "fatal" -> Some Fatal
  | _ -> None

(** The service name written to every line.

    {b Description:} Set once at startup from [AAAS_SERVICE]; defaults to
    ["parser"].

    {b Business Justification:} The [service] field of CLAUDE.md 6.1.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let service = ref "parser"

(** The minimum level written.

    {b Description:} Set once at startup from [AAAS_LOG_LEVEL]; defaults to
    [Info].

    {b Business Justification:} Debug lines are off in normal operation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let min_level = ref Info

(** The output channel.

    {b Description:} [stdout]; tests may redirect it to a buffer through
    {!sink}.

    {b Business Justification:} Logs go to stdout (CLAUDE.md 6.1) and are
    collected by the container runtime.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let sink : (string -> unit) ref =
  ref (fun line ->
      print_string line;
      print_char '\n';
      flush stdout)

(** Builds the JSON of one log line.

    {b Description:} The fixed fields in the order of CLAUDE.md 6.1, then
    [fields]. [trace] supplies [traceId] and [spanId].

    {b Business Justification:} Separated from {!emit} for tests.

    {b Errors:} None.

    {b Side Effects:} reads the clock.

    {b Complexity:} O(f) in the number of extra fields.

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      Yojson.Safe.Util.member "level" (line Info "started") = `String "info"
    ]}

    {b See Also:} {!emit}.

    @param task_id the task, if the line concerns one.
    @param trace the trace context, if known.
    @param fields extra fields.
    @param level the severity.
    @param msg the message.
    @return the JSON object.
    @since parser 0.1.0 *)
let line ?task_id ?trace ?(fields = []) level msg =
  let opt = function Some s -> `String s | None -> `Null in
  `Assoc
    ([
       ("ts", `String (Timestamp.now ()));
       ("level", `String (level_name level));
       ("service", `String !service);
       ("msg", `String msg);
       ("taskId", opt task_id);
       ( "traceId",
         opt (Option.map (fun (t : Trace_context.t) -> t.trace_id) trace) );
       ( "spanId",
         opt (Option.map (fun (t : Trace_context.t) -> t.span_id) trace) );
     ]
    @ fields)

(** Writes one log line if its level is enabled.

    {b Description:} Serializes {!line} on one line and passes it to {!sink}.

    {b Business Justification:} The single logging entry point.

    {b Errors:} None.

    {b Side Effects:} writes to stdout.

    {b Complexity:} O(size of the line).

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      emit ~task_id:"018f..." Info "addition requested"
    ]}

    {b See Also:} {!line}.

    @param task_id the task, if the line concerns one.
    @param trace the trace context, if known.
    @param fields extra fields.
    @param level the severity.
    @param msg the message.
    @since parser 0.1.0 *)
let emit ?task_id ?trace ?fields level msg =
  if rank level >= rank !min_level then
    !sink (Yojson.Safe.to_string (line ?task_id ?trace ?fields level msg))
