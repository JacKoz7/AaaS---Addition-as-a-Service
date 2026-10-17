// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Keys.KeyService
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Handles one key press: records it idempotently, publishes
//                  aaas.key.pressed.v1 and, for `=`, creates the task and
//                  publishes aaas.expression.submitted.v1.
// Related Docs:    CLAUDE.md 3 (steps 2 and 3), CLAUDE.md 4.1,
//                  services/expression-assembler/docs/API.md, ADR-0014

using AaaS.ExpressionAssembler.Events;
using AaaS.ExpressionAssembler.Observability;
using AaaS.ExpressionAssembler.Storage;

namespace AaaS.ExpressionAssembler.Keys;

/// <summary>Outcome of a key press, translated to HTTP by the endpoint.</summary>
/// <remarks>
/// <para><b>Description:</b> exactly one of three shapes: recorded (204), accepted
/// with a task (202) or rejected with a problem (4xx/5xx).</para>
/// <para><b>Business Justification:</b> keeps HTTP concerns out of the domain logic.</para>
/// <para><b>Thread Safety:</b> immutable record; safe.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <param name="Status">HTTP status: 204, 202, or the problem status.</param>
/// <param name="TaskId">Task identifier for 202, otherwise null.</param>
/// <param name="Title">Problem title for statuses of 400 and above, otherwise null.</param>
/// <param name="Detail">Problem detail for statuses of 400 and above, otherwise null.</param>
/// <example><code>KeyResult.Accepted(taskId) // Status 202</code></example>
public sealed record KeyResult(int Status, string? TaskId, string? Title, string? Detail)
{
    /// <summary>Gets the result of a recorded key press other than <c>=</c>.</summary>
    /// <remarks><para><b>Description:</b> status 204.</para>
    /// <para><b>Business Justification:</b> CLAUDE.md 4.1.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public static KeyResult Recorded { get; } = new(204, null, null, null);

    /// <summary>Creates the result of an accepted <c>=</c>.</summary>
    /// <remarks><para><b>Description:</b> status 202 with the task identifier.</para>
    /// <para><b>Business Justification:</b> CLAUDE.md 4.1.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="taskId">Lowercase UUIDv7 of the task.</param>
    /// <returns>The result.</returns>
    public static KeyResult Accepted(string taskId) => new(202, taskId, null, null);

    /// <summary>Creates a problem result.</summary>
    /// <remarks><para><b>Description:</b> rendered as RFC 9457 problem details.</para>
    /// <para><b>Business Justification:</b> CLAUDE.md 4.1 error format.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="status">HTTP status, 400 or above.</param>
    /// <param name="title">Short summary of the problem type.</param>
    /// <param name="detail">Explanation of this occurrence.</param>
    /// <returns>The result.</returns>
    public static KeyResult Problem(int status, string title, string detail) => new(status, null, title, detail);
}

/// <summary>Handles key presses: the core of expression-assembler.</summary>
/// <remarks>
/// <para><b>Description:</b> for every press: validate, store it once per
/// <c>(sessionId, seq)</c>, publish its <c>aaas.key.pressed.v1</c> event if not yet
/// acknowledged. For <c>=</c> additionally: resolve the <c>Idempotency-Key</c> (an
/// existing key returns its task), assemble the expression from the presses before it,
/// create the task atomically with its key and publish
/// <c>aaas.expression.submitted.v1</c>. Events are stored before publishing and marked
/// published after the acknowledgement, so a failed publication is answered with 503
/// and the client's retry republishes the identical event (same <c>eventId</c>).</para>
/// <para>Problems: 400 invalid request or missing <c>Idempotency-Key</c>; 409 when a
/// <c>seq</c> is reused for another key or an <c>Idempotency-Key</c> for another press;
/// 422 when the expression is empty or longer than 64 keys; 503 when the database or
/// the broker is unavailable or the request budget (cancellation) expires.</para>
/// <para><b>Business Justification:</b> CLAUDE.md 3, step 2: clicks become one task per
/// <c>=</c>, never two, whatever the network does.</para>
/// <para><b>Thread Safety:</b> safe for concurrent use; concurrent duplicates are
/// serialised by the database (record identifiers and a transaction).</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>var result = await service.HandleAsync(request, idempotencyKey, ct);</code></example>
public sealed partial class KeyService
{
    /// <summary>Persistence of presses and tasks.</summary>
    /// <remarks><para><b>Description:</b> SurrealDB in production, a fake in tests.</para>
    /// <para><b>Business Justification:</b> own database (CLAUDE.md 1, rule 4).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly IAssemblerStore _store;

    /// <summary>Event publisher.</summary>
    /// <remarks><para><b>Description:</b> Redpanda in production, a fake in tests.</para>
    /// <para><b>Business Justification:</b> events start the addition.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly IEventPublisher _publisher;

    /// <summary>Builder of event envelopes.</summary>
    /// <remarks><para><b>Description:</b> fixes producer, identifiers and timestamps.</para>
    /// <para><b>Business Justification:</b> contract-exact events.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly EventFactory _events;

    /// <summary>Clock; injectable for tests.</summary>
    /// <remarks><para><b>Description:</b> source of reception timestamps.</para>
    /// <para><b>Business Justification:</b> deterministic tests.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly TimeProvider _clock;

    /// <summary>Logger for unavailable dependencies.</summary>
    /// <remarks><para><b>Description:</b> the cause of a 503 is logged, not returned to the
    /// client, so that internal host names never leave the service.</para>
    /// <para><b>Business Justification:</b> information disclosure mitigation (THREAT_MODEL.md).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly ILogger<KeyService> _logger;

    /// <summary>Initializes a new instance of the <see cref="KeyService"/> class.</summary>
    /// <remarks><para><b>Description:</b> stores its dependencies.</para>
    /// <para><b>Business Justification:</b> see the type documentation.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="store">Persistence.</param>
    /// <param name="publisher">Event publisher.</param>
    /// <param name="events">Envelope builder.</param>
    /// <param name="clock">Clock.</param>
    /// <param name="logger">Logger.</param>
    public KeyService(IAssemblerStore store, IEventPublisher publisher, EventFactory events, TimeProvider clock, ILogger<KeyService> logger)
    {
        _store = store;
        _publisher = publisher;
        _events = events;
        _clock = clock;
        _logger = logger;
    }

    /// <summary>Handles one request of <c>POST /api/v1/keys</c>.</summary>
    /// <remarks>
    /// <para><b>Description:</b> see the type documentation for the algorithm and the
    /// problem statuses.</para>
    /// <para><b>Business Justification:</b> the only way input enters AaaS.</para>
    /// <para><b>Side Effects:</b> database reads and writes; publishes up to two events;
    /// updates the metrics of <see cref="AssemblerMetrics"/>; logs the cause of every 503.</para>
    /// <para><b>Complexity:</b> O(n) in the presses of the session for <c>=</c>, O(1) otherwise.</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="request">Deserialized body, or null when the body was empty.</param>
    /// <param name="idempotencyKey">Value of the <c>Idempotency-Key</c> header, or null.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>The result to render.</returns>
    /// <example><code>
    /// var result = await service.HandleAsync(new(session, "=", 3), "a3f1c2", ct);
    /// // result.Status == 202, result.TaskId is a UUIDv7
    /// </code></example>
    public async Task<KeyResult> HandleAsync(KeyPressRequest? request, string? idempotencyKey, CancellationToken cancellationToken)
    {
        var error = KeyPressValidator.Validate(request, idempotencyKey, out var press);
        if (error is not null || press is null)
        {
            AssemblerMetrics.Rejected.WithLabels("invalid").Inc();
            return KeyResult.Problem(400, "Invalid key press", error ?? "invalid request");
        }

        try
        {
            return press.Key == CalculatorKeys.Submit
                ? await SubmitAsync(press, idempotencyKey!, cancellationToken).ConfigureAwait(false)
                : await RecordAsync(press, cancellationToken).ConfigureAwait(false) ?? KeyResult.Recorded;
        }
        catch (DatabaseUnavailableException failure)
        {
            AssemblerMetrics.Rejected.WithLabels("database").Inc();
            LogUnavailable(_logger, "database", failure.Message);
            return KeyResult.Problem(503, "Database unavailable", "the key press could not be stored; retry the same request");
        }
        catch (EventPublishException failure)
        {
            AssemblerMetrics.Rejected.WithLabels("broker").Inc();
            LogUnavailable(_logger, "broker", failure.Message);
            return KeyResult.Problem(503, "Event bus unavailable", "the event could not be published; retry the same request");
        }
        catch (OperationCanceledException)
        {
            AssemblerMetrics.Rejected.WithLabels("deadline").Inc();
            LogUnavailable(_logger, "deadline", $"the request budget of {Program.RequestBudget.TotalMilliseconds} ms expired");
            return KeyResult.Problem(503, "Request deadline exceeded", "a dependency did not answer in time; retry the same request");
        }
    }

    /// <summary>Logs the internal cause of a 503 answer.</summary>
    /// <remarks><para><b>Description:</b> source-generated warning.</para>
    /// <para><b>Business Justification:</b> RUNBOOK diagnosis without exposing internals to clients.</para>
    /// <para><b>Side Effects:</b> one log line. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="logger">Logger.</param>
    /// <param name="dependency">database, broker or deadline.</param>
    /// <param name="reason">Internal cause.</param>
    [LoggerMessage(Level = LogLevel.Warning, Message = "key press answered 503 ({Dependency}): {Reason}")]
    private static partial void LogUnavailable(ILogger logger, string dependency, string reason);

    /// <summary>Stores a press once and publishes its event if needed.</summary>
    /// <remarks>
    /// <para><b>Description:</b> a press with an existing <c>(session, seq)</c> and the same
    /// key is a retry and is accepted; a different key is a conflict.</para>
    /// <para><b>Business Justification:</b> idempotent recording of clicks.</para>
    /// <para><b>Side Effects:</b> database read/write; publishes <c>aaas.key.pressed.v1</c>.</para>
    /// <para><b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para>
    /// </remarks>
    /// <param name="press">Validated press.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>Null when recorded; a 409 problem on conflict.</returns>
    /// <exception cref="DatabaseUnavailableException">The database failed.</exception>
    /// <exception cref="EventPublishException">The broker failed.</exception>
    private async Task<KeyResult?> RecordAsync(KeyPress press, CancellationToken cancellationToken)
    {
        var stored = await _store.GetKeyPressAsync(press.SessionId, press.Seq, cancellationToken).ConfigureAwait(false);
        if (stored is null)
        {
            var now = _clock.GetUtcNow();
            var evt = _events.KeyPressed(press.SessionId, press.Key, press.Seq, now);
            var candidate = new KeyPressRecord(
                press.SessionId, press.Seq, press.Key, EventFactory.FormatTimestamp(now), evt.Json, evt.Traceparent, false, null);
            stored = await _store.TryCreateKeyPressAsync(candidate, cancellationToken).ConfigureAwait(false)
                ? candidate
                : await _store.GetKeyPressAsync(press.SessionId, press.Seq, cancellationToken).ConfigureAwait(false)
                    ?? throw new DatabaseUnavailableException("a concurrently created key press disappeared");
            if (ReferenceEquals(stored, candidate))
            {
                AssemblerMetrics.KeyPresses.WithLabels(press.Key).Inc();
            }
        }

        if (stored.Key != press.Key)
        {
            AssemblerMetrics.Rejected.WithLabels("conflict").Inc();
            return KeyResult.Problem(409, "Sequence number already used", $"seq {press.Seq} of this session was already recorded with key '{stored.Key}'");
        }

        if (!stored.Published)
        {
            await PublishAsync(new OutgoingEvent(EventFactory.KeyPressedTopic, stored.SessionId, stored.EventJson, stored.Traceparent), cancellationToken)
                .ConfigureAwait(false);
            await _store.MarkKeyPressPublishedAsync(stored.SessionId, stored.Seq, cancellationToken).ConfigureAwait(false);
        }

        return null;
    }

    /// <summary>Handles <c>=</c>: records the press, then finds or creates the task.</summary>
    /// <remarks>
    /// <para><b>Description:</b> see the type documentation.</para>
    /// <para><b>Business Justification:</b> one task per <c>Idempotency-Key</c>.</para>
    /// <para><b>Side Effects:</b> database reads and writes; publishes up to two events.</para>
    /// <para><b>Complexity:</b> O(n) in the presses of the session.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para>
    /// </remarks>
    /// <param name="press">Validated <c>=</c> press.</param>
    /// <param name="idempotencyKey">Validated header value.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>202 with the task, or a problem.</returns>
    /// <exception cref="DatabaseUnavailableException">The database failed.</exception>
    /// <exception cref="EventPublishException">The broker failed.</exception>
    private async Task<KeyResult> SubmitAsync(KeyPress press, string idempotencyKey, CancellationToken cancellationToken)
    {
        // TEMPORARY(P6.3): the Idempotency-Key is claimed in the local database;
        // P6.3 replaces the claim with Claim/MarkFailed of the idempotency service.
        var task = await _store.GetTaskByIdempotencyKeyAsync(idempotencyKey, cancellationToken).ConfigureAwait(false);
        if (task is not null)
        {
            return await ReplayAsync(task, press, cancellationToken).ConfigureAwait(false);
        }

        var conflict = await RecordAsync(press, cancellationToken).ConfigureAwait(false);
        if (conflict is not null)
        {
            return conflict;
        }

        var stored = await _store.GetKeyPressAsync(press.SessionId, press.Seq, cancellationToken).ConfigureAwait(false);
        if (stored?.TaskId is { } otherTask)
        {
            // A concurrent retry with the same key may have created the task
            // between the first lookup and now; only another key is a conflict.
            var concurrent = await _store.GetTaskByIdempotencyKeyAsync(idempotencyKey, cancellationToken).ConfigureAwait(false);
            if (concurrent is not null)
            {
                return await ReplayAsync(concurrent, press, cancellationToken).ConfigureAwait(false);
            }

            AssemblerMetrics.Rejected.WithLabels("conflict").Inc();
            return KeyResult.Problem(409, "Key press already submitted", $"this = press already created task {otherTask} with another Idempotency-Key");
        }

        var keys = await _store.GetKeysBeforeAsync(press.SessionId, press.Seq, cancellationToken).ConfigureAwait(false);
        var expression = ExpressionBuilder.Build(keys);
        if (expression.Length == 0 || expression.Length > ExpressionBuilder.MaxLength)
        {
            AssemblerMetrics.Rejected.WithLabels("expression").Inc();
            var reason = expression.Length == 0
                ? "no digit or + key was pressed since the last C or ="
                : $"the expression has {expression.Length} keys; at most {ExpressionBuilder.MaxLength} are allowed";
            return KeyResult.Problem(422, "Expression cannot be submitted", reason);
        }

        var submittedAt = _clock.GetUtcNow();
        var taskId = Guid.CreateVersion7(submittedAt).ToString("D");
        var evt = _events.ExpressionSubmitted(taskId, press.SessionId, expression, submittedAt);
        var candidate = new TaskRecord(
            taskId, press.SessionId, press.Seq, expression, idempotencyKey, EventFactory.FormatTimestamp(submittedAt), evt.Json, evt.Traceparent, false);
        if (!await _store.TryCreateTaskAsync(candidate, cancellationToken).ConfigureAwait(false))
        {
            var winner = await _store.GetTaskByIdempotencyKeyAsync(idempotencyKey, cancellationToken).ConfigureAwait(false)
                ?? throw new DatabaseUnavailableException("a concurrently created task disappeared");
            return await ReplayAsync(winner, press, cancellationToken).ConfigureAwait(false);
        }

        AssemblerMetrics.TasksSubmitted.Inc();
        return await EnsureTaskPublishedAsync(candidate, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>Answers a retried <c>=</c> whose idempotency key already has a task.</summary>
    /// <remarks>
    /// <para><b>Description:</b> the key must belong to the same press (session and seq);
    /// otherwise 409. Publishes the stored events that were not yet acknowledged.</para>
    /// <para><b>Business Justification:</b> the same <c>=</c> returns the same task.</para>
    /// <para><b>Side Effects:</b> may publish the stored events again.</para>
    /// <para><b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para>
    /// </remarks>
    /// <param name="task">Task found for the key.</param>
    /// <param name="press">The retried press.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>202 with the task, or 409.</returns>
    /// <exception cref="DatabaseUnavailableException">The database failed.</exception>
    /// <exception cref="EventPublishException">The broker failed.</exception>
    private async Task<KeyResult> ReplayAsync(TaskRecord task, KeyPress press, CancellationToken cancellationToken)
    {
        if (task.SessionId != press.SessionId || task.Seq != press.Seq)
        {
            AssemblerMetrics.Rejected.WithLabels("conflict").Inc();
            return KeyResult.Problem(409, "Idempotency-Key already used", "this Idempotency-Key was already used for another = press");
        }

        var conflict = await RecordAsync(press, cancellationToken).ConfigureAwait(false);
        return conflict ?? await EnsureTaskPublishedAsync(task, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>Publishes the stored task event unless already acknowledged.</summary>
    /// <remarks>
    /// <para><b>Description:</b> then answers 202 with the task.</para>
    /// <para><b>Business Justification:</b> 202 only after the event is durable.</para>
    /// <para><b>Side Effects:</b> may publish one event and update the task.</para>
    /// <para><b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para>
    /// </remarks>
    /// <param name="task">The task.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>202 with the task.</returns>
    /// <exception cref="DatabaseUnavailableException">The database failed.</exception>
    /// <exception cref="EventPublishException">The broker failed.</exception>
    private async Task<KeyResult> EnsureTaskPublishedAsync(TaskRecord task, CancellationToken cancellationToken)
    {
        if (!task.Published)
        {
            await PublishAsync(new OutgoingEvent(EventFactory.ExpressionSubmittedTopic, task.TaskId, task.EventJson, task.Traceparent), cancellationToken)
                .ConfigureAwait(false);
            await _store.MarkTaskPublishedAsync(task.TaskId, cancellationToken).ConfigureAwait(false);
        }

        return KeyResult.Accepted(task.TaskId);
    }

    /// <summary>Publishes an event and counts the outcome.</summary>
    /// <remarks>
    /// <para><b>Description:</b> wraps <see cref="IEventPublisher.PublishAsync"/>.</para>
    /// <para><b>Business Justification:</b> observable publication.</para>
    /// <para><b>Side Effects:</b> one Kafka produce; increments a counter.</para>
    /// <para><b>Complexity:</b> O(message size).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para>
    /// </remarks>
    /// <param name="outgoing">The event.</param>
    /// <param name="cancellationToken">Cancels the wait.</param>
    /// <returns>A task completing on acknowledgement.</returns>
    /// <exception cref="EventPublishException">The broker failed.</exception>
    private async Task PublishAsync(OutgoingEvent outgoing, CancellationToken cancellationToken)
    {
        try
        {
            await _publisher.PublishAsync(outgoing, cancellationToken).ConfigureAwait(false);
            AssemblerMetrics.EventsPublished.WithLabels(outgoing.Topic, "ok").Inc();
        }
        catch (EventPublishException)
        {
            AssemblerMetrics.EventsPublished.WithLabels(outgoing.Topic, "error").Inc();
            throw;
        }
    }
}
