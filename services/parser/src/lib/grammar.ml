(*
   SPDX-License-Identifier: MIT
   Copyright (c) 2026 AaaS Contributors

   Component:       parser
   Module:          Aaas_parser.Grammar
   Owning Team:     Arithmetic Excellence Center (AEC)
   Classification:  INTERNAL
   Purpose:         Parser of the expression grammar
                    `expression = number "+" number`, producing an AST or a
                    precise rejection reason.
   Related Docs:    services/parser/README.md, services/parser/docs/API.md,
                    ADR-0015
 *)

(** Syntax analysis of AaaS expressions.

    {b Description:} The grammar, in EBNF:
    {v
    expression = number , "+" , number ;
    number     = digit , { digit } ;
    digit      = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
    v}
    Exactly one operator between two numbers; anything else is rejected with a
    {!error} that names the problem and its position. The grammar is not
    recursive, so the parser matches the token list against its few possible
    shapes instead of descending recursively.

    {b Business Justification:} The expression-assembler deliberately forwards
    whatever the user typed ([2++3] is a valid event, ADR-0013); deciding
    whether it is an addition is the parser's responsibility (CLAUDE.md 3, step
    4).

    {b Thread Safety:} pure functions; safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)

(** Why an expression is not an addition.

    {b Description:}
    - [Empty_expression]: no characters at all.
    - [Invalid_character]: a byte outside [0-9+] (see {!Lexer.error}).
    - [Missing_operator]: a single number, such as [23].
    - [Missing_left_operand]: the text starts with [+], such as [+3].
    - [Missing_right_operand]: the text ends with [+], such as [2+].
    - [Unexpected_operator]: a second [+], such as [2++3] or [1+2+3].

    Positions count characters from 1.

    {b Business Justification:} A precise reason in the log and the database
    lets support explain to a user why [2++3] produced no result.

    {b Owner:} Arithmetic Excellence Center (AEC).

    @since parser 0.1.0 *)
type error =
  | Empty_expression
  | Invalid_character of { character : char; position : int }
  | Missing_operator
  | Missing_left_operand
  | Missing_right_operand
  | Unexpected_operator of { position : int }

(** Stable machine-readable code of a rejection.

    {b Description:} snake_case codes used as the [reason] label of the
    [parser_expressions_rejected_total] metric and as the prefix of the stored
    reason.

    {b Business Justification:} Dashboards and alerts group rejections without
    parsing free text.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      error_code Missing_operator = "missing_operator"
    ]}

    {b See Also:} {!error_message}, {!Metrics}.

    @param error a rejection.
    @return its code.
    @since parser 0.1.0 *)
let error_code = function
  | Empty_expression -> "empty_expression"
  | Invalid_character _ -> "invalid_character"
  | Missing_operator -> "missing_operator"
  | Missing_left_operand -> "missing_left_operand"
  | Missing_right_operand -> "missing_right_operand"
  | Unexpected_operator _ -> "unexpected_operator"

(** Human-readable description of a rejection.

    {b Description:} One English sentence fragment including the position where
    one is known.

    {b Business Justification:} Stored in [processed_events.reason] and written
    to the log for support staff.

    {b Errors:} None.

    {b Side Effects:} None.

    {b Complexity:} O(1).

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      error_message (Unexpected_operator { position = 3 })
      = "unexpected '+' at position 3: exactly one operator is allowed"
    ]}

    {b See Also:} {!error_code}.

    @param error a rejection.
    @return its description.
    @since parser 0.1.0 *)
let error_message = function
  | Empty_expression -> "the expression is empty"
  | Invalid_character { character; position } ->
      Printf.sprintf "invalid character %C at position %d" character position
  | Missing_operator -> "no '+' operator: an addition needs two operands"
  | Missing_left_operand -> "the expression starts with '+': no left operand"
  | Missing_right_operand -> "the expression ends with '+': no right operand"
  | Unexpected_operator { position } ->
      Printf.sprintf
        "unexpected '+' at position %d: exactly one operator is allowed"
        position

(** Parses the text of an expression into an AST.

    {b Description:} Tokenizes [text] ({!Lexer.tokenize}) and matches the tokens
    against the grammar of this module. Leading zeros are allowed and removed
    ([007+1] is [7+1]). Operands of any length are accepted: the range is not a
    syntax rule ({!Operands}).

    {b Business Justification:} The core responsibility of the parser (CLAUDE.md
    2, row 10).

    {b Errors:} [Error e] with the first problem found, scanning from the left
    (see {!error}).

    {b Side Effects:} None.

    {b Complexity:} O(n) time and memory in the length of [text].

    {b Thread Safety:} safe.

    {b Owner:} Arithmetic Excellence Center (AEC).

    {b Example:}
    {[
      parse "2+3"
      = Ok (Ast.Addition { augend = Ast.numeral "2"; addend = Ast.numeral "3" })
      && parse "2++3" = Error (Unexpected_operator { position = 3 })
    ]}

    {b See Also:} {!Ast}, {!Processor.handle}.

    @param text the expression text, as in [payload.expression].
    @return the AST, or why the text is not an addition.
    @since parser 0.1.0 *)
let parse text =
  match Lexer.tokenize text with
  | Error { character; position } ->
      Error (Invalid_character { character; position })
  | Ok tokens -> (
      match tokens with
      | [] -> Error Empty_expression
      | { token = Lexer.Plus; _ } :: _ -> Error Missing_left_operand
      | [ { token = Lexer.Number _; _ } ] -> Error Missing_operator
      | { token = Lexer.Number _; _ } :: { token = Lexer.Number _; _ } :: _ ->
          (* The lexer never yields two adjacent numbers. *)
          Error Missing_operator
      | [ { token = Lexer.Number _; _ }; { token = Lexer.Plus; _ } ] ->
          Error Missing_right_operand
      | { token = Lexer.Number _; _ }
        :: { token = Lexer.Plus; _ }
        :: { token = Lexer.Plus; position }
        :: _ ->
          Error (Unexpected_operator { position })
      | [
       { token = Lexer.Number left; _ };
       { token = Lexer.Plus; _ };
       { token = Lexer.Number right; _ };
      ] ->
          Ok
            (Ast.Addition
               { augend = Ast.numeral left; addend = Ast.numeral right })
      | { token = Lexer.Number _; _ }
        :: { token = Lexer.Plus; _ }
        :: { token = Lexer.Number _; _ }
        :: { token = _; position }
        :: _ ->
          (* After a complete addition only a further operator can follow,
             because the lexer merges adjacent digits. *)
          Error (Unexpected_operator { position }))
