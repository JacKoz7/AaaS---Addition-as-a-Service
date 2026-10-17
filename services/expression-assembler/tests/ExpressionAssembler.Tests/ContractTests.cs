// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Tests.ContractTests
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Validates the events the service produces against the JSON
//                  Schemas in contracts/events (format assertion on).
// Related Docs:    ADR-0013, contracts/events/README.md

using System.Text.Json;
using AaaS.ExpressionAssembler.Events;
using Json.Schema;

namespace AaaS.ExpressionAssembler.Tests;

/// <summary>Contract tests of the produced events.</summary>
/// <remarks>
/// <para><b>Description:</b> the envelope and the event schemas are loaded from
/// <c>contracts/events</c> into one registry; every event built by
/// <see cref="EventFactory"/> must validate with <c>date-time</c> asserted.</para>
/// <para><b>Business Justification:</b> a producer that breaks its contract breaks the
/// parser and stopwatch; CLAUDE.md 6.4 requires contract tests.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
public sealed class ContractTests
{
    /// <summary>Factory under test, with the production producer name.</summary>
    /// <remarks><para><b>Description:</b> <c>expression-assembler</c>.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly EventFactory _factory = new("expression-assembler");

    /// <summary>A key press event validates against aaas.key.pressed.v1.</summary>
    /// <remarks><para><b>Description:</b> every key, including = and C.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="key">Pressed key.</param>
    [Theory]
    [InlineData("0")]
    [InlineData("9")]
    [InlineData("+")]
    [InlineData("=")]
    [InlineData("C")]
    public void KeyPressedMatchesItsContract(string key)
    {
        var evt = _factory.KeyPressed("5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90", key, 42, DateTimeOffset.UtcNow);

        AssertValid(EventFactory.KeyPressedTopic, evt.Json);
    }

    /// <summary>An expression event validates against aaas.expression.submitted.v1.</summary>
    /// <remarks><para><b>Description:</b> a well-formed and a malformed expression.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="expression">Expression.</param>
    [Theory]
    [InlineData("2+3")]
    [InlineData("2++3")]
    public void ExpressionSubmittedMatchesItsContract(string expression)
    {
        var now = DateTimeOffset.UtcNow;
        var evt = _factory.ExpressionSubmitted(Guid.CreateVersion7(now).ToString("D"), "5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90", expression, now);

        AssertValid(EventFactory.ExpressionSubmittedTopic, evt.Json);
    }

    /// <summary>The validation itself rejects an event of the wrong producer.</summary>
    /// <remarks><para><b>Description:</b> proves the test can fail.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    [Fact]
    public void WrongProducerIsRejected()
    {
        var evt = new EventFactory("parser").KeyPressed("5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90", "1", 0, DateTimeOffset.UtcNow);

        Assert.False(Evaluate(EventFactory.KeyPressedTopic, evt.Json).IsValid);
    }

    /// <summary>Asserts that an event validates, listing the errors otherwise.</summary>
    /// <remarks><para><b>Description:</b> flattens the evaluation results.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="topic">Topic of the schema.</param>
    /// <param name="json">Serialized event.</param>
    private static void AssertValid(string topic, string json)
    {
        var results = Evaluate(topic, json);
        var errors = (results.Details ?? [])
            .Where(d => d.Errors is { Count: > 0 })
            .SelectMany(d => d.Errors!.Select(e => $"{d.InstanceLocation}: {e.Value}"));
        Assert.True(results.IsValid, $"{json} does not match {topic}: {string.Join("; ", errors)}");
    }

    /// <summary>Evaluates an event against the schema of a topic.</summary>
    /// <remarks><para><b>Description:</b> builds the envelope first so that the event
    /// schema resolves its <c>$ref</c>; formats are asserted.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="topic">Topic of the schema.</param>
    /// <param name="json">Serialized event.</param>
    /// <returns>The evaluation results in list format.</returns>
    private static EvaluationResults Evaluate(string topic, string json)
    {
        var events = Path.Combine(TestPaths.Contracts, "events");
        var build = new BuildOptions { SchemaRegistry = new SchemaRegistry() };
        JsonSchema.FromFile(Path.Combine(events, "envelope.v1.schema.json"), build);
        var schema = JsonSchema.FromFile(Path.Combine(events, $"{topic}.schema.json"), build);
        using var document = JsonDocument.Parse(json);
        return schema.Evaluate(
            document.RootElement,
            new EvaluationOptions { OutputFormat = OutputFormat.List, RequireFormatValidation = true });
    }
}
