(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Timestamp
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Wall-clock time in milliseconds and its AaaS text form
                    (UTC, exactly three fractional digits, `Z`).
   Related Docs:    contracts/events/envelope.v1.schema.json ($defs/timestamp),
                    ADR-0013, ADR-0015
 *)

(** Timestamps of events and logs.

    {b Description:} AaaS writes every timestamp as [YYYY-MM-DDTHH:MM:SS.mmmZ]
    in UTC (ADR-0013).

    {b Business Justification:} A fixed form keeps timestamps comparable and
    hashes over them reproducible across 28 languages.

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** Current wall-clock time in milliseconds since the Unix epoch.

    {b Description:} [Unix.gettimeofday] truncated to milliseconds.

    {b Business Justification:} [occurredAt] of produced events and the
    timestamp part of UUIDv7.

    {b Errors:} None.

    {b Side Effects:} reads the system clock.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      now_ms () > 1_700_000_000_000L
    ]}

    {b See Also:} {!format}.

    @param unit no argument.
    @return milliseconds since 1970-01-01T00:00:00Z.
    @since parser 0.1.0 *)
let now_ms () = Int64.of_float (Unix.gettimeofday () *. 1000.)

(** Formats milliseconds since the epoch in the AaaS form.

    {b Description:} UTC calendar date and time with exactly three fractional
    digits and the [Z] designator.

    {b Business Justification:} The only timestamp form accepted by the event
    schemas.

    {b Errors:} None for non-negative input.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      format 1_792_152_000_000L = "2026-10-16T12:00:00.000Z"
    ]}

    {b See Also:} {!now}.

    @param ms milliseconds since the epoch, non-negative.
    @return the timestamp text.
    @since parser 0.1.0 *)
let format ms =
  let seconds = Int64.div ms 1000L in
  let millis = Int64.to_int (Int64.rem ms 1000L) in
  let t = Unix.gmtime (Int64.to_float seconds) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ" (t.tm_year + 1900)
    (t.tm_mon + 1) t.tm_mday t.tm_hour t.tm_min t.tm_sec millis

(** The current time in the AaaS form.

    {b Description:} [format (now_ms ())].

    {b Business Justification:} Log lines and database timestamps.

    {b Errors:} None.

    {b Side Effects:} reads the system clock.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      String.length (now ()) = 24
    ]}

    {b See Also:} {!format}.

    @param unit no argument.
    @return the current timestamp text.
    @since parser 0.1.0 *)
let now () = format (now_ms ())
