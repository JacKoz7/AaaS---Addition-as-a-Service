(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Lexer
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Splits the text of an expression into tokens: runs of
                    decimal digits and the plus operator.
   Related Docs:    services/parser/README.md, ADR-0015
 *)

(** Lexical analysis of AaaS expressions.

    {b Description:} The alphabet of an expression is the calculator keyboard
    minus [=] and [C]: the digits [0]..[9] and [+]
    (contracts/events/aaas.expression.submitted.v1.schema.json). Consecutive
    digits form one {!Number} token.

    {b Business Justification:} Separating lexing from parsing keeps each stage
    small enough to be verified exhaustively by unit tests.

    {b Thread Safety:} pure functions; safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** A token of an expression.

    {b Description:} [Number digits] is a maximal run of decimal digits as typed
    (leading zeros kept); [Plus] is the addition operator.

    {b Business Justification:} The two key kinds that may appear in an
    expression.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type token = Number of string | Plus

(** A token with the position of its first character.

    {b Description:} [position] counts characters from 1, as shown to a human
    reading the expression.

    {b Business Justification:} Rejection reasons name the position of the
    problem ("unexpected '+' at position 3").

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type located = { token : token; position : int }

(** A lexical error: a character outside the alphabet.

    {b Description:} [character] is the offending character and [position] its
    1-based position.

    {b Business Justification:} The event contract already restricts the
    alphabet; the lexer still refuses other characters so that the parser never
    trusts its input (defence in depth, THREAT_MODEL.md).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type error = { character : char; position : int }

(** Tests whether a character is a decimal digit.

    {b Description:} ['0'..'9'] only; no other Unicode digits exist in the input
    because it is processed byte by byte.

    {b Business Justification:} Shared by the scanner of {!tokenize}.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      is_digit '7' = true && is_digit '+' = false
    ]}

    {b See Also:} {!tokenize}.

    @param c a character.
    @return [true] for a decimal digit.
    @since parser 0.1.0 *)
let is_digit c = c >= '0' && c <= '9'

(** Splits an expression into tokens.

    {b Description:} Scans [text] from left to right. A digit starts or extends
    a {!Number}; [+] yields {!Plus}; any other byte stops the scan with an
    {!error}. The empty text yields no tokens.

    {b Business Justification:} First stage of turning the typed text into an
    AST (CLAUDE.md 3, step 4).

    {b Errors:} [Error e] for the first byte outside [0-9+].

    {b Side Effects:} None.

    {b Complexity:} O(n) time and memory in the length of [text].

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      tokenize "12+3"
      = Ok
          [
            { token = Number "12"; position = 1 };
            { token = Plus; position = 3 };
            { token = Number "3"; position = 4 };
          ]
    ]}

    {b See Also:} {!Grammar.parse}.

    @param text the expression text.
    @return the tokens in order, or the first lexical error.
    @since parser 0.1.0 *)
let tokenize text =
  let length = String.length text in
  let rec number_end i =
    if i < length && is_digit text.[i] then number_end (i + 1) else i
  in
  let rec scan i acc =
    if i >= length then Ok (List.rev acc)
    else
      match text.[i] with
      | '+' -> scan (i + 1) ({ token = Plus; position = i + 1 } :: acc)
      | c when is_digit c ->
          let stop = number_end i in
          let token = Number (String.sub text i (stop - i)) in
          scan stop ({ token; position = i + 1 } :: acc)
      | character -> Error { character; position = i + 1 }
  in
  scan 0 []
