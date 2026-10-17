(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Ast
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Abstract syntax tree of an AaaS expression and its JSON
                    form stored in the AST cache.
   Related Docs:    services/parser/README.md, services/parser/docs/API.md,
                    ADR-0015
 *)

(** Abstract syntax tree of an AaaS expression.

    {b Description:} The only expression AaaS accepts is the addition of two
    natural numbers written in decimal ([2+3]). A numeral keeps its digits as
    text in canonical form (no leading zeros, ["0"] for zero), so the tree can
    represent any operand the keyboard can type, including operands that are far
    outside the range of the addition contract; the range is checked later
    ({!Operands}).

    {b Business Justification:} The AST is the hand-over between "text the user
    typed" and "numbers the arithmetic services work with". Keeping it explicit
    allows the cache to store it and future operators to extend it without
    touching the arithmetic.

    {b Thread Safety:} immutable values; safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** A natural number written in decimal.

    {b Description:} [digits] is non-empty, contains only ['0'..'9'] and has no
    leading zero unless it is exactly ["0"]. Values are built only by
    {!val-numeral}, which enforces the invariant.

    {b Business Justification:} Operands of any length can be represented
    exactly, without integer overflow, so that a mistyped 40-digit number is
    reported as out of range instead of silently wrapping around.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type numeral = { digits : string }

(** An expression.

    {b Description:} [Addition] of an [augend] (left operand, [a]) and an
    [addend] (right operand, [b]), in the order typed by the user.

    {b Business Justification:} AaaS adds two integers and nothing else
    (CLAUDE.md 1); a variant leaves room for the operator registry (P2.16)
    without changing the cache format of additions.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type t = Addition of { augend : numeral; addend : numeral }

(** Builds a numeral from a run of decimal digits.

    {b Description:} Strips leading zeros (["007"] becomes ["7"], ["000"]
    becomes ["0"]).

    {b Business Justification:} The calculator lets the user type leading zeros;
    the value of the number does not depend on them.

    {b Errors:} [Invalid_argument] when [text] is empty or contains a character
    other than a decimal digit.

    {b Side Effects:} None.

    {b Complexity:} O(n) time and memory in the length of [text].

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      (numeral "007").digits = "7"
    ]}

    {b See Also:} {!Lexer}.

    @param text decimal digits, at least one.
    @return the canonical numeral.
    @since parser 0.1.0 *)
let numeral text =
  if text = "" || not (String.for_all (fun c -> c >= '0' && c <= '9') text) then
    invalid_arg "Ast.numeral: expected decimal digits";
  let length = String.length text in
  let rec first_significant i =
    if i < length - 1 && text.[i] = '0' then first_significant (i + 1) else i
  in
  let start = first_significant 0 in
  { digits = String.sub text start (length - start) }

(** Renders an expression in its canonical text form.

    {b Description:} Numerals in canonical form joined by [+], so [to_string] of
    the AST of ["02+3"] is ["2+3"].

    {b Business Justification:} Readable log messages and test failures.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(n) time and memory in the number of digits.

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      to_string (Addition { augend = numeral "2"; addend = numeral "3" })
      = "2+3"
    ]}

    {b See Also:} {!to_json}.

    @param expression the expression to render.
    @return the canonical text.
    @since parser 0.1.0 *)
let to_string (Addition { augend; addend }) =
  augend.digits ^ "+" ^ addend.digits

(** Serializes a numeral as JSON.

    {b Description:} [{"type":"numeral","digits":"..."}].

    {b Business Justification:} Part of the AST cache format.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1) time and memory (the digits are shared).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      numeral_to_json (numeral "5")
      = `Assoc [ ("type", `String "numeral"); ("digits", `String "5") ]
    ]}

    {b See Also:} {!to_json}.

    @param n the numeral.
    @return its JSON object.
    @since parser 0.1.0 *)
let numeral_to_json n =
  `Assoc [ ("type", `String "numeral"); ("digits", `String n.digits) ]

(** Serializes an expression as JSON.

    {b Description:}
    [{"type":"addition","augend":<numeral>,"addend":<numeral>}]. The format is
    stored in [ast_cache.ast_json] and must stay readable by {!of_json} of every
    later version.

    {b Business Justification:} The AST cache (CLAUDE.md 2, parser database)
    stores parsed expressions so that a repeated expression is not parsed again.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1) time and memory.

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      Yojson.Safe.to_string
        (to_json (Addition { augend = numeral "2"; addend = numeral "3" }))
      = {|{"type":"addition","augend":{"type":"numeral","digits":"2"},"addend":{"type":"numeral","digits":"3"}}|}
    ]}

    {b See Also:} {!of_json}, {!Store.cache_put}.

    @param expression the expression.
    @return its JSON object.
    @since parser 0.1.0 *)
let to_json (Addition { augend; addend }) =
  `Assoc
    [
      ("type", `String "addition");
      ("augend", numeral_to_json augend);
      ("addend", numeral_to_json addend);
    ]

(** Reads a numeral from its JSON object.

    {b Description:} Accepts [{"type":"numeral","digits":"..."}] in any field
    order and re-applies the invariant of {!val-numeral}.

    {b Business Justification:} Part of reading the AST cache.

    {b Errors:} [Error message] when the object has another shape or the digits
    are not decimal.

    {b Side Effects:} None.

    {b Complexity:} O(n) time and memory in the number of digits.

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      numeral_of_json (numeral_to_json (numeral "9")) = Ok (numeral "9")
    ]}

    {b See Also:} {!of_json}.

    @param json a JSON value.
    @return the numeral or an error message.
    @since parser 0.1.0 *)
let numeral_of_json = function
  | `Assoc fields -> (
      match (List.assoc_opt "type" fields, List.assoc_opt "digits" fields) with
      | Some (`String "numeral"), Some (`String digits) -> (
          try Ok (numeral digits) with Invalid_argument m -> Error m)
      | _ -> Error "numeral: expected type \"numeral\" and string digits")
  | _ -> Error "numeral: expected an object"

(** Reads an expression from its JSON object.

    {b Description:} Inverse of {!to_json}: [of_json (to_json e) = Ok e].

    {b Business Justification:} A cache hit returns the stored AST instead of
    parsing the text again.

    {b Errors:} [Error message] when the JSON is not an AST written by
    {!to_json}; the caller then parses the text and overwrites nothing (the
    cache entry stays, see {!Store.cache_find}).

    {b Side Effects:} None.

    {b Complexity:} O(n) time and memory in the number of digits.

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      let e = Addition { augend = numeral "2"; addend = numeral "3" } in
      of_json (to_json e) = Ok e
    ]}

    {b See Also:} {!to_json}.

    @param json a JSON value.
    @return the expression or an error message.
    @since parser 0.1.0 *)
let of_json = function
  | `Assoc fields -> (
      match
        ( List.assoc_opt "type" fields,
          List.assoc_opt "augend" fields,
          List.assoc_opt "addend" fields )
      with
      | Some (`String "addition"), Some augend, Some addend -> (
          match (numeral_of_json augend, numeral_of_json addend) with
          | Ok augend, Ok addend -> Ok (Addition { augend; addend })
          | Error m, _ | _, Error m -> Error m)
      | _ -> Error "ast: expected an addition with augend and addend")
  | _ -> Error "ast: expected an object"
