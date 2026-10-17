(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Operands
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Converts the numerals of an addition AST into the integer
                    operands of aaas.addition.requested.v1, refusing values
                    the event contract cannot carry.
   Related Docs:    contracts/events/envelope.v1.schema.json ($defs/operand),
                    CLAUDE.md 1 (range 0-99 999), ADR-0015
 *)

(** Operands of the addition contract.

    {b Description:} [aaas.addition.requested.v1] carries [a] and [b] as
    integers in [0..99 999] (the [operand] definition of the envelope). This
    module turns the numerals of an {!Ast.t} into such integers.

    {b Business Justification:} A producer must never publish an event its
    schema rejects (ADR-0013). Until the parser calls [validator] (P2.17), the
    range of the contract is enforced here.

    {b Thread Safety:} pure functions; safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** Largest operand of the addition contract.

    {b Description:} [99_999], the [maximum] of [$defs/operand] in
    contracts/events/envelope.v1.schema.json.

    {b Business Justification:} The functional range of AaaS (CLAUDE.md 1).

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
let max_operand = 99_999

(** An operand outside the contract range.

    {b Description:} [operand] is ["a"] or ["b"]; [digits] is the canonical
    numeral that does not fit.

    {b Business Justification:} Stored as the rejection reason, so support can
    tell the user which operand was too large.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type error = Out_of_range of { operand : string; digits : string }

(** Stable machine-readable code of a range rejection.

    {b Description:} Always ["operand_out_of_range"].

    {b Business Justification:} Same vocabulary as {!Grammar.error_code} for
    metrics and stored reasons.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      error_code (Out_of_range { operand = "a"; digits = "100000" })
      = "operand_out_of_range"
    ]}

    {b See Also:} {!error_message}.

    @param error a range rejection.
    @return its code.
    @since parser 0.1.0 *)
let error_code (Out_of_range _) = "operand_out_of_range"

(** Human-readable description of a range rejection.

    {b Description:} Names the operand, its value and the allowed range. Values
    longer than 20 digits are shortened with an ellipsis.

    {b Business Justification:} Stored in [processed_events.reason].

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1) (the shown digits are bounded).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      error_message (Out_of_range { operand = "b"; digits = "100000" })
      = "operand b = 100000 is outside the range 0..99999"
    ]}

    {b See Also:} {!error_code}.

    @param error a range rejection.
    @return its description.
    @since parser 0.1.0 *)
let error_message (Out_of_range { operand; digits }) =
  let shown =
    if String.length digits <= 20 then digits
    else String.sub digits 0 20 ^ "..."
  in
  Printf.sprintf "operand %s = %s is outside the range 0..%d" operand shown
    max_operand

(** Converts one numeral into a contract operand.

    {b Description:} A canonical numeral has no leading zeros, so more than five
    digits always means a value above {!max_operand}; up to five digits are
    converted with [int_of_string], which cannot overflow.

    {b Business Justification:} See the module documentation.

    {b Errors:} [Error (Out_of_range _)] above {!max_operand}.

    {b Side Effects:} None.

    {b Complexity:} O(1) (at most five digits are converted).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      to_operand "a" (Ast.numeral "99999") = Ok 99999
    ]}

    {b See Also:} {!of_ast}.

    @param name ["a"] or ["b"], used in the error.
    @param numeral the canonical numeral.
    @return the integer value in [0..max_operand].
    @since parser 0.1.0 *)
let to_operand name (numeral : Ast.numeral) =
  let error =
    Error (Out_of_range { operand = name; digits = numeral.digits })
  in
  if String.length numeral.digits > 5 then error
  else
    let value = int_of_string numeral.digits in
    if value > max_operand then error else Ok value

(** Extracts the operands [(a, b)] of an addition.

    {b Description:} [a] is the augend and [b] the addend, in the order the user
    typed them; reordering is the commutator's job (P2.15).

    {b Business Justification:} Produces the payload of
    [aaas.addition.requested.v1].

    {b Errors:} [Error (Out_of_range _)] for the first operand, [a] before [b],
    that exceeds {!max_operand}.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      of_ast
        (Ast.Addition { augend = Ast.numeral "2"; addend = Ast.numeral "3" })
      = Ok (2, 3)
    ]}

    {b See Also:} {!Processor.handle}.

    @param ast a parsed addition.
    @return the operands [(a, b)].
    @since parser 0.1.0 *)
let of_ast (Ast.Addition { augend; addend }) =
  (* TEMPORARY(P2.17): the range is checked locally until the parser calls
     the validator service, which then owns this rule (CLAUDE.md 2, row 11). *)
  match to_operand "a" augend with
  | Error e -> Error e
  | Ok a -> (
      match to_operand "b" addend with Error e -> Error e | Ok b -> Ok (a, b))
