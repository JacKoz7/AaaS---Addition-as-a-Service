// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Tests.Fakes
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         In-memory test doubles of the store and the publisher,
//                  with the same idempotency semantics as SurrealDB and a
//                  switch to simulate an unavailable broker.
// Related Docs:    services/expression-assembler/README.md (Testing)

using System.Collections.Concurrent;
using AaaS.ExpressionAssembler.Events;
using AaaS.ExpressionAssembler.Storage;

namespace AaaS.ExpressionAssembler.Tests;

/// <summary>In-memory <see cref="IAssemblerStore"/>.</summary>
/// <remarks>
/// <para><b>Description:</b> creates never overwrite; the task, its key and the link from
/// the key press are written under one lock, mirroring the SurrealDB transaction.</para>
/// <para><b>Business Justification:</b> fast, deterministic tests of the key logic.</para>
/// <para><b>Thread Safety:</b> safe (one lock).</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
internal sealed class InMemoryStore : IAssemblerStore
{
    /// <summary>Key presses by (session, seq).</summary>
    /// <remarks><para><b>Description:</b> guarded by <see cref="_gate"/>.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly Dictionary<(string, long), KeyPressRecord> _presses = [];

    /// <summary>Tasks by idempotency key.</summary>
    /// <remarks><para><b>Description:</b> guarded by <see cref="_gate"/>.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly Dictionary<string, TaskRecord> _tasks = [];

    /// <summary>Lock of both dictionaries.</summary>
    /// <remarks><para><b>Description:</b> serialises every operation.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly Lock _gate = new();

    /// <summary>Gets or sets a value indicating whether every call fails as an unavailable database.</summary>
    /// <remarks><para><b>Description:</b> simulates an outage.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public bool Down { get; set; }

    /// <summary>Gets a snapshot of the stored tasks.</summary>
    /// <remarks><para><b>Description:</b> for assertions.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public IReadOnlyList<TaskRecord> Tasks
    {
        get
        {
            lock (_gate)
            {
                return _tasks.Values.ToList();
            }
        }
    }

    /// <inheritdoc/>
    public Task<KeyPressRecord?> GetKeyPressAsync(string sessionId, long seq, CancellationToken cancellationToken)
    {
        Check();
        lock (_gate)
        {
            return Task.FromResult(_presses.GetValueOrDefault((sessionId, seq)));
        }
    }

    /// <inheritdoc/>
    public Task<bool> TryCreateKeyPressAsync(KeyPressRecord record, CancellationToken cancellationToken)
    {
        Check();
        lock (_gate)
        {
            return Task.FromResult(_presses.TryAdd((record.SessionId, record.Seq), record));
        }
    }

    /// <inheritdoc/>
    public Task<IReadOnlyList<string>> GetKeysBeforeAsync(string sessionId, long beforeSeq, CancellationToken cancellationToken)
    {
        Check();
        lock (_gate)
        {
            IReadOnlyList<string> keys = _presses.Values
                .Where(p => p.SessionId == sessionId && p.Seq < beforeSeq)
                .OrderBy(p => p.Seq)
                .Select(p => p.Key)
                .ToList();
            return Task.FromResult(keys);
        }
    }

    /// <inheritdoc/>
    public Task MarkKeyPressPublishedAsync(string sessionId, long seq, CancellationToken cancellationToken)
    {
        Check();
        lock (_gate)
        {
            _presses[(sessionId, seq)] = _presses[(sessionId, seq)] with { Published = true };
        }

        return Task.CompletedTask;
    }

    /// <inheritdoc/>
    public Task<TaskRecord?> GetTaskByIdempotencyKeyAsync(string idempotencyKey, CancellationToken cancellationToken)
    {
        Check();
        lock (_gate)
        {
            return Task.FromResult(_tasks.GetValueOrDefault(idempotencyKey));
        }
    }

    /// <inheritdoc/>
    public Task<bool> TryCreateTaskAsync(TaskRecord task, CancellationToken cancellationToken)
    {
        Check();
        lock (_gate)
        {
            if (!_tasks.TryAdd(task.IdempotencyKey, task))
            {
                return Task.FromResult(false);
            }

            _presses[(task.SessionId, task.Seq)] = _presses[(task.SessionId, task.Seq)] with { TaskId = task.TaskId };
            return Task.FromResult(true);
        }
    }

    /// <inheritdoc/>
    public Task MarkTaskPublishedAsync(string taskId, CancellationToken cancellationToken)
    {
        Check();
        lock (_gate)
        {
            var entry = _tasks.First(t => t.Value.TaskId == taskId);
            _tasks[entry.Key] = entry.Value with { Published = true };
        }

        return Task.CompletedTask;
    }

    /// <inheritdoc/>
    public Task<bool> PingAsync(CancellationToken cancellationToken) => Task.FromResult(!Down);

    /// <summary>Fails when the store is down.</summary>
    /// <remarks><para><b>Description:</b> raises the production exception type.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <exception cref="DatabaseUnavailableException">When <see cref="Down"/> is true.</exception>
    private void Check()
    {
        if (Down)
        {
            throw new DatabaseUnavailableException("simulated outage");
        }
    }
}

/// <summary>Recording <see cref="IEventPublisher"/>.</summary>
/// <remarks>
/// <para><b>Description:</b> keeps every published event; <see cref="FailNext"/> makes the
/// next publications fail like an unreachable broker.</para>
/// <para><b>Business Justification:</b> tests of publication and retry behaviour.</para>
/// <para><b>Thread Safety:</b> safe (concurrent queue, interlocked counter).</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
internal sealed class FakePublisher : IEventPublisher
{
    /// <summary>Number of publications that still have to fail.</summary>
    /// <remarks><para><b>Description:</b> decremented atomically.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private int _failures;

    /// <summary>Gets the published events in order.</summary>
    /// <remarks><para><b>Description:</b> for assertions.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public ConcurrentQueue<OutgoingEvent> Published { get; } = new();

    /// <summary>Gets or sets a value indicating whether the broker is reported reachable.</summary>
    /// <remarks><para><b>Description:</b> drives the health endpoint.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public bool Reachable { get; set; } = true;

    /// <summary>Makes the next publications fail.</summary>
    /// <remarks><para><b>Description:</b> each failure throws <see cref="EventPublishException"/>.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="count">Number of publications to fail.</param>
    public void FailNext(int count) => Interlocked.Exchange(ref _failures, count);

    /// <inheritdoc/>
    public Task PublishAsync(OutgoingEvent outgoing, CancellationToken cancellationToken)
    {
        if (Interlocked.Decrement(ref _failures) >= 0)
        {
            throw new EventPublishException("simulated broker outage", new TimeoutException());
        }

        Interlocked.Exchange(ref _failures, 0);
        Published.Enqueue(outgoing);
        return Task.CompletedTask;
    }

    /// <inheritdoc/>
    public bool IsBrokerReachable() => Reachable;
}

/// <summary>Clock that advances one millisecond per reading.</summary>
/// <remarks>
/// <para><b>Description:</b> starts at 2026-10-17T10:00:00Z; distinct readings give
/// distinct, ordered timestamps.</para>
/// <para><b>Business Justification:</b> deterministic timestamps in tests.</para>
/// <para><b>Thread Safety:</b> safe (interlocked).</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
internal sealed class SteppingClock : TimeProvider
{
    /// <summary>Milliseconds since the start instant.</summary>
    /// <remarks><para><b>Description:</b> incremented on every reading.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private long _ticks;

    /// <summary>Gets the first instant returned.</summary>
    /// <remarks><para><b>Description:</b> 2026-10-17T10:00:00.000Z.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public static DateTimeOffset Start { get; } = new(2026, 10, 17, 10, 0, 0, TimeSpan.Zero);

    /// <inheritdoc/>
    public override DateTimeOffset GetUtcNow() => Start.AddMilliseconds(Interlocked.Increment(ref _ticks));
}

/// <summary>Store whose reads observe the cancellation token, like the HTTP client.</summary>
/// <remarks>
/// <para><b>Description:</b> wraps <see cref="InMemoryStore"/>; every call throws
/// <see cref="OperationCanceledException"/> when the token is cancelled.</para>
/// <para><b>Business Justification:</b> tests of the request budget.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
internal sealed class CancellingStore : IAssemblerStore
{
    /// <summary>The wrapped store.</summary>
    /// <remarks><para><b>Description:</b> receives the calls that are not cancelled.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly InMemoryStore _inner = new();

    /// <inheritdoc/>
    public Task<KeyPressRecord?> GetKeyPressAsync(string sessionId, long seq, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return _inner.GetKeyPressAsync(sessionId, seq, cancellationToken);
    }

    /// <inheritdoc/>
    public Task<bool> TryCreateKeyPressAsync(KeyPressRecord record, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return _inner.TryCreateKeyPressAsync(record, cancellationToken);
    }

    /// <inheritdoc/>
    public Task<IReadOnlyList<string>> GetKeysBeforeAsync(string sessionId, long beforeSeq, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return _inner.GetKeysBeforeAsync(sessionId, beforeSeq, cancellationToken);
    }

    /// <inheritdoc/>
    public Task MarkKeyPressPublishedAsync(string sessionId, long seq, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return _inner.MarkKeyPressPublishedAsync(sessionId, seq, cancellationToken);
    }

    /// <inheritdoc/>
    public Task<TaskRecord?> GetTaskByIdempotencyKeyAsync(string idempotencyKey, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return _inner.GetTaskByIdempotencyKeyAsync(idempotencyKey, cancellationToken);
    }

    /// <inheritdoc/>
    public Task<bool> TryCreateTaskAsync(TaskRecord task, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return _inner.TryCreateTaskAsync(task, cancellationToken);
    }

    /// <inheritdoc/>
    public Task MarkTaskPublishedAsync(string taskId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return _inner.MarkTaskPublishedAsync(taskId, cancellationToken);
    }

    /// <inheritdoc/>
    public Task<bool> PingAsync(CancellationToken cancellationToken) => _inner.PingAsync(cancellationToken);
}
