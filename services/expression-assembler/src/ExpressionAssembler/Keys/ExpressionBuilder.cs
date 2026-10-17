// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Keys.ExpressionBuilder
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Assembles the expression submitted by `=` from the key
//                  presses of a session.
// Related Docs:    CLAUDE.md 3 (step 2), ADR-0013 (expression payload),
//                  services/expression-assembler/docs/API.md

using System.Text;

namespace AaaS.ExpressionAssembler.Keys;

/// <summary>Builds the expression of a session from its key presses.</summary>
/// <remarks>
/// <para><b>Description:</b> The expression consists of the digit and <c>+</c>
/// keys pressed after the most recent <c>C</c> or <c>=</c> (or since the session
/// started), in <c>seq</c> order. The builder does not check the syntax: <c>2++3</c>
/// is a valid expression to submit and the parser rejects it (ADR-0013). It only
/// enforces the bounds of the event contract: at least one key and at most
/// <see cref="MaxLength"/> keys.</para>
/// <para><b>Business Justification:</b> the assembler turns clicks into an
/// expression; parsing belongs to the parser (CLAUDE.md 3).</para>
/// <para><b>Thread Safety:</b> stateless; safe.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>ExpressionBuilder.Build(["2", "+", "3"]) // "2+3"</code></example>
/// <seealso cref="KeyService"/>
public static class ExpressionBuilder
{
    /// <summary>Maximum number of keys in an expression.</summary>
    /// <remarks><para><b>Description:</b> Equals the <c>maxLength</c> of
    /// <c>payload.expression</c> in <c>aaas.expression.submitted.v1</c>.</para>
    /// <para><b>Business Justification:</b> the longest valid addition is 11 keys
    /// (<c>99999+99999</c>); 64 leaves room for typing mistakes the parser reports.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public const int MaxLength = 64;

    /// <summary>Assembles the expression from the keys pressed before <c>=</c>.</summary>
    /// <remarks>
    /// <para><b>Description:</b> Scans <paramref name="keysInOrder"/> (all presses of
    /// the session with a smaller <c>seq</c> than the submitting <c>=</c>, ascending)
    /// and keeps the keys after the last <c>C</c> or <c>=</c>.</para>
    /// <para><b>Business Justification:</b> see the type documentation.</para>
    /// <para><b>Side Effects:</b> None.</para>
    /// <para><b>Complexity:</b> O(n) time and memory in the number of presses.</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="keysInOrder">Keys of the session in ascending <c>seq</c> order, each one
    /// of <see cref="CalculatorKeys.All"/>.</param>
    /// <returns>The expression; empty when nothing was typed since the last <c>C</c> or <c>=</c>.</returns>
    /// <example><code>
    /// ExpressionBuilder.Build(["1", "C", "2", "+", "3"]) // "2+3"
    /// ExpressionBuilder.Build(["2", "+", "3", "=", "4"]) // "4"
    /// </code></example>
    public static string Build(IEnumerable<string> keysInOrder)
    {
        var expression = new StringBuilder();
        foreach (var key in keysInOrder)
        {
            if (key is CalculatorKeys.Clear or CalculatorKeys.Submit)
            {
                expression.Clear();
            }
            else
            {
                expression.Append(key);
            }
        }

        return expression.ToString();
    }
}
