(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Uuid_v7
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Generates time-ordered UUIDv7 identifiers (RFC 9562) for
                    the eventId of produced events.
   Related Docs:    RFC 9562 section 5.7, ADR-0013 (identifier formats),
                    ADR-0015
 *)

(** UUID version 7.

    {b Description:} Layout (RFC 9562, 5.7): 48 bits of Unix time in
    milliseconds, 4 bits of version ([0111]), 12 random bits, 2 bits of variant
    ([10]) and 62 random bits, written in the lowercase 8-4-4-4-12 form.

    {b Business Justification:} Every [eventId] in AaaS is a lowercase UUIDv7
    (ADR-0013); no maintained OCaml library generates version 7.

    {b Thread Safety:} see {!Entropy}.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** Formats 16 bytes as a lowercase UUID string.

    {b Description:} Inserts hyphens after the 4th, 6th, 8th and 10th byte.

    {b Business Justification:} Canonical textual form of RFC 9562.

    {b Errors:} [Invalid_argument] if [b] is not 16 bytes long.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Example:}
    {[
      format (Bytes.make 16 '\x00') = "00000000-0000-0000-0000-000000000000"
    ]}

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b See Also:} {!generate}.

    @param b exactly 16 bytes.
    @return the 36-character UUID.
    @since parser 0.1.0 *)
let format b =
  if Bytes.length b <> 16 then invalid_arg "Uuid_v7.format: expected 16 bytes";
  let h = Entropy.hex b in
  String.concat "-"
    [
      String.sub h 0 8;
      String.sub h 8 4;
      String.sub h 12 4;
      String.sub h 16 4;
      String.sub h 20 12;
    ]

(** Builds a UUIDv7 from a timestamp and random bytes.

    {b Description:} Deterministic core of {!generate}: writes the 48-bit
    timestamp big-endian into bytes 0..5, takes bytes 6..15 from [random] and
    overwrites the version and variant bits.

    {b Business Justification:} Lets the tests check the layout with fixed
    inputs.

    {b Errors:} [Invalid_argument] if [random] is shorter than 10 bytes.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      of_parts ~unix_ms:0x018f3c2e7b1aL ~random:(Bytes.make 10 '\x00')
      = "018f3c2e-7b1a-7000-8000-000000000000"
    ]}

    {b See Also:} {!generate}.

    @param unix_ms milliseconds since the Unix epoch, [0 <= unix_ms < 2^48].
    @param random at least 10 random bytes.
    @return the UUID string.
    @since parser 0.1.0 *)
let of_parts ~unix_ms ~random =
  if Bytes.length random < 10 then invalid_arg "Uuid_v7.of_parts: random";
  let b = Bytes.create 16 in
  for i = 0 to 5 do
    let shift = 8 * (5 - i) in
    Bytes.set b i
      (Char.chr
         (Int64.to_int
            (Int64.logand (Int64.shift_right_logical unix_ms shift) 0xffL)))
  done;
  Bytes.blit random 0 b 6 10;
  Bytes.set b 6 (Char.chr (0x70 lor (Char.code (Bytes.get b 6) land 0x0f)));
  Bytes.set b 8 (Char.chr (0x80 lor (Char.code (Bytes.get b 8) land 0x3f)));
  format b

(** Generates a new UUIDv7 for the current time.

    {b Description:} {!of_parts} with the wall clock and 10 bytes from
    {!Entropy.bytes}. Identifiers generated in the same millisecond are unique
    (74 random bits) but not ordered among themselves, which RFC 9562 permits.

    {b Business Justification:} The [eventId] of every produced
    [aaas.addition.requested.v1] event.

    {b Errors:} [Sys_error] from {!Entropy.bytes}.

    {b Side Effects:} reads the clock and the random source.

    {b Complexity:} O(1).

    {b Thread Safety:} see {!Entropy}.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      (generate ()).[14] = '7'
    ]}

    {b See Also:} {!Timestamp.now_ms}.

    @param unit no argument.
    @return a new lowercase UUIDv7.
    @since parser 0.1.0 *)
let generate () =
  of_parts ~unix_ms:(Timestamp.now_ms ()) ~random:(Entropy.bytes 10)
