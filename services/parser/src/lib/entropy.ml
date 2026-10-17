(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Entropy
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Random bytes from the kernel CSPRNG for identifiers
                    (UUIDv7 random bits, trace and span identifiers).
   Related Docs:    RFC 9562 (UUIDv7), W3C Trace Context, ADR-0015
 *)

(** Random bytes for identifiers.

    {b Description:} Reads [/dev/urandom], which never blocks once the kernel
    pool is initialised. The channel is opened on first use and kept open for
    the lifetime of the process.

    {b Business Justification:} Event, trace and span identifiers must be unique
    across restarts and replicas; the OCaml [Random] module is seeded per
    process and not designed for that.

    {b Thread Safety:} not safe for concurrent use from several system threads;
    the service runs one Lwt thread, where calls never interleave.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** The open channel on [/dev/urandom].

    {b Description:} A lazily opened binary input channel.

    {b Business Justification:} One [open] per process instead of one per
    identifier.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let source = lazy (open_in_bin "/dev/urandom")

(** Returns [n] random bytes.

    {b Description:} Reads exactly [n] bytes from {!source}.

    {b Business Justification:} Randomness for {!Uuid_v7.generate} and
    {!Trace_context}.

    {b Errors:} [Sys_error] if [/dev/urandom] cannot be opened (not on a Linux
    or macOS host); [End_of_file] never happens in practice.

    {b Side Effects:} reads from the kernel CSPRNG; opens it on first use.

    {b Complexity:} O(n) time and memory.

    {b Thread Safety:} see the module documentation.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      Bytes.length (bytes 16) = 16
    ]}

    {b See Also:} {!Uuid_v7.generate}.

    @param n number of bytes, [n >= 0].
    @return [n] random bytes.
    @since parser 0.1.0 *)
let bytes n =
  let buffer = Bytes.create n in
  really_input (Lazy.force source) buffer 0 n;
  buffer

(** Encodes bytes as lowercase hexadecimal.

    {b Description:} Two characters per byte, most significant nibble first.

    {b Business Justification:} Every textual identifier in AaaS (UUIDs, trace
    identifiers) is lowercase hexadecimal (ADR-0013).

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(n) time and memory.

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      hex (Bytes.of_string "\x01\xab") = "01ab"
    ]}

    {b See Also:} {!Uuid_v7.format}.

    @param b the bytes.
    @return their hexadecimal form.
    @since parser 0.1.0 *)
let hex b =
  String.concat ""
    (List.init (Bytes.length b) (fun i ->
         Printf.sprintf "%02x" (Char.code (Bytes.get b i))))
