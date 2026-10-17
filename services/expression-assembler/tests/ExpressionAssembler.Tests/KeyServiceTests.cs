// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Tests.KeyServiceTests
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Tests of KeyService: recording, task creation, idempotency,
//                  conflicts, validation and behaviour when dependencies fail.
// Related Docs:    services/expression-assembler/docs/API.md, CLAUDE.md 4.1

using System.Text.Json;
using AaaS.ExpressionAssembler.Events;
using AaaS.ExpressionAssembler.Keys;
using Microsoft.Extensions.Logging.Abstractions;

namespace AaaS.ExpressionAssembler.Tests;

/// <summary>Tests of <see cref="KeyService"/>.</summary>
/// <remarks>
/// <para><b>Description:</b> each test builds a service over <see cref="InMemoryStore"/>
/// and <see cref="FakePublisher"/>.</para>
/// <para><b>Business Justification:</b> one <c>=</c> must yield exactly one task, whatever
/// the client retries and the dependencies do.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
public sealed class KeyServiceTests
{
    /// <summary>Session used by the tests.</summary>
    /// <remarks><para><b>Description:</b> canonical lowercase UUID.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private const string Session = "5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90";

    /// <summary>Store under test.</summary>
    /// <remarks><para><b>Description:</b> fresh per test.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly InMemoryStore _store = new();

    /// <summary>Publisher under test.</summary>
    /// <remarks><para><b>Description:</b> fresh per test.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly FakePublisher _publisher = new();

    /// <summary>Service under test.</summary>
    /// <remarks><para><b>Description:</b> wired to the fakes.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly KeyService _service;

    /// <summary>Initializes a new instance of the <see cref="KeyServiceTests"/> class.</summary>
    /// <remarks><para><b>Description:</b> wires the service.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public KeyServiceTests() =>
        _service = new KeyService(_store, _publisher, new EventFactory("expression-assembler"), new SteppingClock(), NullLogger<KeyService>.Instance);

    /// <summary>A digit is recorded with 204 and one key press event keyed by session.</summary>
    /// <remarks><para><b>Description:</b> checks status, topic, key and taskId null.</para>
    /// <para><b>Business Justification:</b> CLAUDE.md 4.1 (204 for keys other than =).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task DigitIsRecordedAndPublished()
    {
        var result = await Press("2", 0);

        Assert.Equal(204, result.Status);
        var evt = Assert.Single(_publisher.Published);
        Assert.Equal(EventFactory.KeyPressedTopic, evt.Topic);
        Assert.Equal(Session, evt.Key);
        using var doc = JsonDocument.Parse(evt.Json);
        Assert.Equal(JsonValueKind.Null, doc.RootElement.GetProperty("taskId").ValueKind);
        Assert.Equal("2", doc.RootElement.GetProperty("payload").GetProperty("key").GetString());
    }

    /// <summary>Typing 2 + 3 = yields 202 and an expression event with "2+3".</summary>
    /// <remarks><para><b>Description:</b> the task event is keyed by taskId and carries it.</para>
    /// <para><b>Business Justification:</b> the M1 scenario (CLAUDE.md 9.2).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task EqualsSubmitsTheExpression()
    {
        await Press("2", 0);
        await Press("+", 1);
        await Press("3", 2);
        var result = await Press("=", 3, "key-1");

        Assert.Equal(202, result.Status);
        Assert.True(Guid.TryParse(result.TaskId, out var taskId));
        Assert.Equal(7, taskId.Version);
        var submitted = Assert.Single(_publisher.Published, e => e.Topic == EventFactory.ExpressionSubmittedTopic);
        Assert.Equal(result.TaskId, submitted.Key);
        using var doc = JsonDocument.Parse(submitted.Json);
        Assert.Equal("2+3", doc.RootElement.GetProperty("payload").GetProperty("expression").GetString());
        Assert.Contains("\"expression\":\"2+3\"", submitted.Json, StringComparison.Ordinal);
        Assert.Equal(result.TaskId, doc.RootElement.GetProperty("taskId").GetString());
        Assert.Equal(4, _publisher.Published.Count(e => e.Topic == EventFactory.KeyPressedTopic));
    }

    /// <summary>Retrying = with the same key returns the same task and publishes nothing new.</summary>
    /// <remarks><para><b>Description:</b> idempotency of the submit.</para>
    /// <para><b>Business Justification:</b> CLAUDE.md 3, step 2 (same key, same task).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task RetriedEqualsReturnsTheSameTask()
    {
        await Press("1", 0);
        var first = await Press("=", 1, "key-1");
        var published = _publisher.Published.Count;
        var second = await Press("=", 1, "key-1");

        Assert.Equal(202, second.Status);
        Assert.Equal(first.TaskId, second.TaskId);
        Assert.Equal(published, _publisher.Published.Count);
        Assert.Single(_store.Tasks);
    }

    /// <summary>A retried digit press is accepted and not republished.</summary>
    /// <remarks><para><b>Description:</b> same session, seq and key.</para>
    /// <para><b>Business Justification:</b> idempotent recording of clicks.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task RetriedDigitIsIdempotent()
    {
        await Press("4", 0);
        var again = await Press("4", 0);

        Assert.Equal(204, again.Status);
        Assert.Single(_publisher.Published);
    }

    /// <summary>A reused seq with another key is a 409 conflict.</summary>
    /// <remarks><para><b>Description:</b> the first press wins.</para>
    /// <para><b>Business Justification:</b> a seq identifies one press.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task ReusedSeqWithAnotherKeyConflicts()
    {
        await Press("4", 0);
        var conflict = await Press("5", 0);

        Assert.Equal(409, conflict.Status);
    }

    /// <summary>An idempotency key reused for another = press is a 409 conflict.</summary>
    /// <remarks><para><b>Description:</b> no second task is created.</para>
    /// <para><b>Business Justification:</b> one key, one task.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task ReusedIdempotencyKeyForAnotherPressConflicts()
    {
        await Press("1", 0);
        await Press("=", 1, "key-1");
        await Press("2", 2);
        var conflict = await Press("=", 3, "key-1");

        Assert.Equal(409, conflict.Status);
        Assert.Single(_store.Tasks);
    }

    /// <summary>The same = press with a different idempotency key is a 409 conflict.</summary>
    /// <remarks><para><b>Description:</b> the press already created a task.</para>
    /// <para><b>Business Justification:</b> one press, one task.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task SamePressWithAnotherIdempotencyKeyConflicts()
    {
        await Press("1", 0);
        await Press("=", 1, "key-1");
        var conflict = await Press("=", 1, "key-2");

        Assert.Equal(409, conflict.Status);
    }

    /// <summary>C and a previous = reset the expression.</summary>
    /// <remarks><para><b>Description:</b> 1 C 2 + 3 = submits "2+3", then 4 = submits "4".</para>
    /// <para><b>Business Justification:</b> the clear key and consecutive additions.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task ClearAndEqualsResetTheExpression()
    {
        foreach (var (key, seq) in new[] { ("1", 0L), ("C", 1L), ("2", 2L), ("+", 3L), ("3", 4L) })
        {
            await Press(key, seq);
        }

        await Press("=", 5, "key-1");
        await Press("4", 6);
        await Press("=", 7, "key-2");

        Assert.Equal(["2+3", "4"], _store.Tasks.OrderBy(t => t.Seq).Select(t => t.Expression));
    }

    /// <summary>= without any typed key is a 422 problem.</summary>
    /// <remarks><para><b>Description:</b> empty expressions are not submitted.</para>
    /// <para><b>Business Justification:</b> the contract requires a non-empty expression.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task EmptyExpressionIsUnprocessable()
    {
        var result = await Press("=", 0, "key-1");

        Assert.Equal(422, result.Status);
        Assert.Empty(_store.Tasks);
    }

    /// <summary>An expression longer than 64 keys is a 422 problem.</summary>
    /// <remarks><para><b>Description:</b> 65 digits then =.</para>
    /// <para><b>Business Justification:</b> the contract bounds the expression.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task TooLongExpressionIsUnprocessable()
    {
        for (var seq = 0; seq < 65; seq++)
        {
            await Press("9", seq);
        }

        var result = await Press("=", 65, "key-1");

        Assert.Equal(422, result.Status);
    }

    /// <summary>= without the Idempotency-Key header is a 400 problem.</summary>
    /// <remarks><para><b>Description:</b> nothing is stored.</para>
    /// <para><b>Business Justification:</b> CLAUDE.md 4.1.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task EqualsWithoutIdempotencyKeyIsRejected()
    {
        var result = await Press("=", 0);

        Assert.Equal(400, result.Status);
        Assert.Contains("Idempotency-Key", result.Detail, StringComparison.Ordinal);
        Assert.Empty(_publisher.Published);
    }

    /// <summary>A broker failure answers 503; the retry publishes the identical event.</summary>
    /// <remarks><para><b>Description:</b> the stored event keeps its eventId.</para>
    /// <para><b>Business Justification:</b> consumers deduplicate by eventId (CLAUDE.md 4.2).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task BrokerFailureIsRetriedWithTheSameEvent()
    {
        await Press("7", 0);
        _publisher.FailNext(1);
        var failed = await Press("=", 1, "key-1");
        var retried = await Press("=", 1, "key-1");

        Assert.Equal(503, failed.Status);
        Assert.Equal(202, retried.Status);
        var task = Assert.Single(_store.Tasks);
        var submitted = Assert.Single(_publisher.Published, e => e.Topic == EventFactory.ExpressionSubmittedTopic);
        Assert.Equal(task.EventJson, submitted.Json);
        Assert.True(Assert.Single(_store.Tasks).Published);
    }

    /// <summary>A database failure answers 503.</summary>
    /// <remarks><para><b>Description:</b> no event is published.</para>
    /// <para><b>Business Justification:</b> nothing is announced that is not stored.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task DatabaseFailureIsUnavailable()
    {
        _store.Down = true;
        var result = await Press("1", 0);

        Assert.Equal(503, result.Status);
        Assert.Empty(_publisher.Published);
    }

    /// <summary>An expired request budget answers 503.</summary>
    /// <remarks><para><b>Description:</b> the cancellation token is already cancelled.</para>
    /// <para><b>Business Justification:</b> 503 from the service instead of 504 from the gateway.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task ExpiredBudgetIsUnavailable()
    {
        using var expired = new CancellationTokenSource();
        await expired.CancelAsync();
        var service = new KeyService(new CancellingStore(), _publisher, new EventFactory("expression-assembler"), new SteppingClock(), NullLogger<KeyService>.Instance);

        var result = await service.HandleAsync(new KeyPressRequest(Session, "1", 0), null, expired.Token);

        Assert.Equal(503, result.Status);
        Assert.Equal("Request deadline exceeded", result.Title);
    }

    /// <summary>Concurrent retries of one = create exactly one task.</summary>
    /// <remarks><para><b>Description:</b> 20 parallel requests with the same key.</para>
    /// <para><b>Business Justification:</b> exactly-once task creation under races.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task ConcurrentRetriesCreateOneTask()
    {
        await Press("8", 0);
        var results = await Task.WhenAll(Enumerable.Range(0, 20).Select(_ => Task.Run(() => Press("=", 1, "key-1"))));

        Assert.All(results, r => Assert.Equal(202, r.Status));
        Assert.Single(results.Select(r => r.TaskId).Distinct());
        Assert.Single(_store.Tasks);
    }

    /// <summary>Sends one key press to the service.</summary>
    /// <remarks><para><b>Description:</b> uses the test session.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="key">Key.</param>
    /// <param name="seq">Position.</param>
    /// <param name="idempotencyKey">Header value, or null.</param>
    /// <returns>The result.</returns>
    private Task<KeyResult> Press(string key, long seq, string? idempotencyKey = null) =>
        _service.HandleAsync(new KeyPressRequest(Session, key, seq), idempotencyKey, TestContext.Current.CancellationToken);
}
