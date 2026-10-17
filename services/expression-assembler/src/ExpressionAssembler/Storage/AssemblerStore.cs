// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Storage.AssemblerStore
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Persistence of key presses, tasks and idempotency keys in
//                  SurrealDB (tables key_press, task, idempotency_key), with
//                  the stored event of each record for identical retries.
// Related Docs:    migrations/0001_initial_schema.surql, ADR-0014,
//                  services/expression-assembler/docs/DATA_CLASSIFICATION.md

using System.Text.Json.Nodes;

namespace AaaS.ExpressionAssembler.Storage;

/// <summary>Persistence used by <see cref="Keys.KeyService"/>.</summary>
/// <remarks>
/// <para><b>Description:</b> every write is idempotent by record identifier: creating an
/// existing record reports false instead of overwriting it.</para>
/// <para><b>Business Justification:</b> clients retry; retries must not create a second
/// key press or a second task.</para>
/// <para><b>Thread Safety:</b> implementations must be safe for concurrent use.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>var existing = await store.GetKeyPressAsync(session, seq, ct);</code></example>
public interface IAssemblerStore
{
    /// <summary>Reads one key press.</summary>
    /// <remarks><para><b>Description:</b> by session and position.</para>
    /// <para><b>Business Justification:</b> detects retried presses.</para>
    /// <para><b>Side Effects:</b> one database read. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="sessionId">Session.</param>
    /// <param name="seq">Position.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>The record, or null when absent.</returns>
    /// <exception cref="DatabaseUnavailableException">The database could not be queried.</exception>
    Task<KeyPressRecord?> GetKeyPressAsync(string sessionId, long seq, CancellationToken cancellationToken);

    /// <summary>Creates a key press unless one exists with the same session and position.</summary>
    /// <remarks><para><b>Description:</b> never overwrites.</para>
    /// <para><b>Business Justification:</b> idempotent recording of presses.</para>
    /// <para><b>Side Effects:</b> one database write. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="record">The press to store.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>True when created, false when it already existed.</returns>
    /// <exception cref="DatabaseUnavailableException">The database could not be queried.</exception>
    Task<bool> TryCreateKeyPressAsync(KeyPressRecord record, CancellationToken cancellationToken);

    /// <summary>Lists the keys of a session pressed before a position.</summary>
    /// <remarks><para><b>Description:</b> ascending by position, positions strictly
    /// smaller than <paramref name="beforeSeq"/>.</para>
    /// <para><b>Business Justification:</b> input of <see cref="Keys.ExpressionBuilder"/>.</para>
    /// <para><b>Side Effects:</b> one database read. <b>Complexity:</b> O(n log n) in the
    /// presses of the session (index scan).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="sessionId">Session.</param>
    /// <param name="beforeSeq">Exclusive upper bound of positions.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>The keys in order.</returns>
    /// <exception cref="DatabaseUnavailableException">The database could not be queried.</exception>
    Task<IReadOnlyList<string>> GetKeysBeforeAsync(string sessionId, long beforeSeq, CancellationToken cancellationToken);

    /// <summary>Marks the event of a key press as published.</summary>
    /// <remarks><para><b>Description:</b> sets <c>published = true</c>.</para>
    /// <para><b>Business Justification:</b> retries skip already published events.</para>
    /// <para><b>Side Effects:</b> one database write. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="sessionId">Session.</param>
    /// <param name="seq">Position.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>A task that completes when the update is stored.</returns>
    /// <exception cref="DatabaseUnavailableException">The database could not be queried.</exception>
    Task MarkKeyPressPublishedAsync(string sessionId, long seq, CancellationToken cancellationToken);

    /// <summary>Finds the task created with an idempotency key.</summary>
    /// <remarks><para><b>Description:</b> looks up <c>task</c> by its indexed
    /// <c>idempotency_key</c> field.</para>
    /// <para><b>Business Justification:</b> the same <c>=</c> returns the same task.</para>
    /// <para><b>Side Effects:</b> one database read. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="idempotencyKey">Header value.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>The task, or null when the key is unknown.</returns>
    /// <exception cref="DatabaseUnavailableException">The database could not be queried.</exception>
    Task<TaskRecord?> GetTaskByIdempotencyKeyAsync(string idempotencyKey, CancellationToken cancellationToken);

    /// <summary>Creates a task, its idempotency key and the link from its key press atomically.</summary>
    /// <remarks><para><b>Description:</b> one transaction; nothing is written when the
    /// idempotency key or the task already exists.</para>
    /// <para><b>Business Justification:</b> exactly one task per idempotency key, even
    /// under concurrent retries.</para>
    /// <para><b>Side Effects:</b> one transactional database write. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="task">The task to create.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>True when created, false when the idempotency key was already taken.</returns>
    /// <exception cref="DatabaseUnavailableException">The database could not be queried.</exception>
    Task<bool> TryCreateTaskAsync(TaskRecord task, CancellationToken cancellationToken);

    /// <summary>Marks the event of a task as published.</summary>
    /// <remarks><para><b>Description:</b> sets <c>published = true</c>.</para>
    /// <para><b>Business Justification:</b> retries skip already published events.</para>
    /// <para><b>Side Effects:</b> one database write. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="taskId">Task.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>A task that completes when the update is stored.</returns>
    /// <exception cref="DatabaseUnavailableException">The database could not be queried.</exception>
    Task MarkTaskPublishedAsync(string taskId, CancellationToken cancellationToken);

    /// <summary>Checks that the database answers a trivial query.</summary>
    /// <remarks><para><b>Description:</b> used by <c>GET /health</c>.</para>
    /// <para><b>Business Justification:</b> an assembler without its database cannot accept presses.</para>
    /// <para><b>Side Effects:</b> one database read. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>True when the database answered.</returns>
    Task<bool> PingAsync(CancellationToken cancellationToken);
}

/// <summary>A stored key press.</summary>
/// <remarks>
/// <para><b>Description:</b> identified by <c>(SessionId, Seq)</c>. <paramref name="EventJson"/>
/// is the <c>aaas.key.pressed.v1</c> envelope; <paramref name="Published"/> becomes true
/// once the broker acknowledged it.</para>
/// <para><b>Business Justification:</b> the key presses are the raw material of every expression.</para>
/// <para><b>Thread Safety:</b> immutable record; safe.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <param name="SessionId">Lowercase UUID of the session.</param>
/// <param name="Seq">Position of the press in the session.</param>
/// <param name="Key">Pressed key.</param>
/// <param name="ReceivedAt">Contract timestamp of reception.</param>
/// <param name="EventJson">Serialized <c>aaas.key.pressed.v1</c> event.</param>
/// <param name="Traceparent">Trace context of the event.</param>
/// <param name="Published">Whether the event was acknowledged by the broker.</param>
/// <param name="TaskId">Task created by this press (only for <c>=</c>), or null.</param>
/// <example><code>new KeyPressRecord(session, 0, "2", "2026-10-17T10:00:00.000Z", json, tp, false, null)</code></example>
public sealed record KeyPressRecord(
    string SessionId,
    long Seq,
    string Key,
    string ReceivedAt,
    string EventJson,
    string Traceparent,
    bool Published,
    string? TaskId);

/// <summary>A stored task: the expression submitted by one <c>=</c>.</summary>
/// <remarks>
/// <para><b>Description:</b> created together with its idempotency key and the link from
/// the submitting key press, in one transaction.</para>
/// <para><b>Business Justification:</b> one <c>Idempotency-Key</c>, one task (CLAUDE.md 3, step 2).</para>
/// <para><b>Thread Safety:</b> immutable record; safe.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <param name="TaskId">Lowercase UUIDv7 of the task.</param>
/// <param name="SessionId">Session that submitted it.</param>
/// <param name="Seq">Position of the submitting <c>=</c>.</param>
/// <param name="Expression">The submitted expression.</param>
/// <param name="IdempotencyKey">Value of the <c>Idempotency-Key</c> header.</param>
/// <param name="SubmittedAt">Contract timestamp of the <c>=</c> press.</param>
/// <param name="EventJson">Serialized <c>aaas.expression.submitted.v1</c> event.</param>
/// <param name="Traceparent">Trace context of the event.</param>
/// <param name="Published">Whether the event was acknowledged by the broker.</param>
/// <example><code>new TaskRecord(taskId, session, 3, "2+3", key, at, json, tp, false)</code></example>
public sealed record TaskRecord(
    string TaskId,
    string SessionId,
    long Seq,
    string Expression,
    string IdempotencyKey,
    string SubmittedAt,
    string EventJson,
    string Traceparent,
    bool Published);

/// <summary>SurrealDB implementation of <see cref="IAssemblerStore"/>.</summary>
/// <remarks>
/// <para><b>Description:</b> record identifiers carry the natural keys:
/// <c>key_press:[sessionId, seq]</c>, <c>task:⟨taskId⟩</c> and
/// <c>idempotency_key:⟨key⟩</c>, so a duplicate create fails with
/// <c>AlreadyExists</c>. The schema is defined by the migrations. Identifier
/// variables are cast with <c>&lt;string&gt;</c> because the RPC endpoint turns a
/// JSON string that looks like a UUID into a SurrealDB <c>uuid</c> value, which a
/// <c>string</c> field rejects.</para>
/// <para><b>Business Justification:</b> the service's own database (CLAUDE.md 1, rule 4).</para>
/// <para><b>Thread Safety:</b> safe for concurrent use.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>var store = new SurrealAssemblerStore(client);</code></example>
public sealed class SurrealAssemblerStore : IAssemblerStore
{
    /// <summary>Columns of <c>key_press</c> returned by reads.</summary>
    /// <remarks><para><b>Description:</b> the record identifier is not returned; the
    /// natural key columns identify the record.</para>
    /// <para><b>Business Justification:</b> one projection for every read.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private const string KeyPressColumns =
        "session_id, seq, key, <string>received_at AS received_at, event, traceparent, published, task_id";

    /// <summary>Columns of <c>task</c> returned by reads.</summary>
    /// <remarks><para><b>Description:</b> the task identifier is stored as a field.</para>
    /// <para><b>Business Justification:</b> one projection for every read.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private const string TaskColumns =
        "task_id, session_id, seq, expression, idempotency_key, <string>submitted_at AS submitted_at, event, traceparent, published";

    /// <summary>The SurrealDB client.</summary>
    /// <remarks><para><b>Description:</b> carries timeouts and retries.</para>
    /// <para><b>Business Justification:</b> resilient database access.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly SurrealClient _client;

    /// <summary>Initializes a new instance of the <see cref="SurrealAssemblerStore"/> class.</summary>
    /// <remarks><para><b>Description:</b> stores the client.</para>
    /// <para><b>Business Justification:</b> see the type documentation.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="client">SurrealDB client.</param>
    public SurrealAssemblerStore(SurrealClient client) => _client = client;

    /// <inheritdoc/>
    public async Task<KeyPressRecord?> GetKeyPressAsync(string sessionId, long seq, CancellationToken cancellationToken)
    {
        var results = await QueryAsync(
            $"SELECT {KeyPressColumns} FROM ONLY type::record('key_press', [<string>$sid, $n]);",
            new() { ["sid"] = sessionId, ["n"] = seq },
            cancellationToken).ConfigureAwait(false);
        return results[0].Result is JsonObject row ? ToKeyPress(row) : null;
    }

    /// <inheritdoc/>
    public async Task<bool> TryCreateKeyPressAsync(KeyPressRecord record, CancellationToken cancellationToken)
    {
        var results = await _client.QueryAsync(
            "CREATE type::record('key_press', [<string>$sid, $n]) CONTENT { session_id: <string>$sid, seq: $n, key: <string>$k, "
            + "received_at: <datetime>$at, event: $evt, traceparent: $tp, published: $pub, task_id: NONE } RETURN NONE;",
            new()
            {
                ["sid"] = record.SessionId,
                ["n"] = record.Seq,
                ["k"] = record.Key,
                ["at"] = record.ReceivedAt,
                ["evt"] = record.EventJson,
                ["tp"] = record.Traceparent,
                ["pub"] = record.Published,
            },
            cancellationToken).ConfigureAwait(false);
        return CreatedOrExisting(results[0]);
    }

    /// <inheritdoc/>
    public async Task<IReadOnlyList<string>> GetKeysBeforeAsync(string sessionId, long beforeSeq, CancellationToken cancellationToken)
    {
        var results = await QueryAsync(
            "SELECT key, seq FROM key_press WHERE session_id = <string>$sid AND seq < $lim ORDER BY seq ASC;",
            new() { ["sid"] = sessionId, ["lim"] = beforeSeq },
            cancellationToken).ConfigureAwait(false);
        return results[0].Result is JsonArray rows
            ? rows.Select(row => row!["key"]!.GetValue<string>()).ToList()
            : [];
    }

    /// <inheritdoc/>
    public Task MarkKeyPressPublishedAsync(string sessionId, long seq, CancellationToken cancellationToken) =>
        QueryAsync(
            "UPDATE type::record('key_press', [<string>$sid, $n]) SET published = true RETURN NONE;",
            new() { ["sid"] = sessionId, ["n"] = seq },
            cancellationToken);

    /// <inheritdoc/>
    public async Task<TaskRecord?> GetTaskByIdempotencyKeyAsync(string idempotencyKey, CancellationToken cancellationToken)
    {
        var results = await QueryAsync(
            $"SELECT {TaskColumns} FROM task WHERE idempotency_key = <string>$k LIMIT 1;",
            new() { ["k"] = idempotencyKey },
            cancellationToken).ConfigureAwait(false);
        return results[0].Result is JsonArray { Count: > 0 } rows ? ToTask(rows[0]!.AsObject()) : null;
    }

    /// <inheritdoc/>
    public async Task<bool> TryCreateTaskAsync(TaskRecord task, CancellationToken cancellationToken)
    {
        var results = await _client.QueryAsync(
            "BEGIN TRANSACTION;"
            + "CREATE type::record('idempotency_key', <string>$k) CONTENT { task: type::record('task', <string>$tid), created_at: <datetime>$at } RETURN NONE;"
            + "CREATE type::record('task', <string>$tid) CONTENT { task_id: <string>$tid, session_id: <string>$sid, seq: $n, expression: $expr, "
            + "idempotency_key: <string>$k, submitted_at: <datetime>$at, event: $evt, traceparent: $tp, published: $pub } RETURN NONE;"
            + "UPDATE type::record('key_press', [<string>$sid, $n]) SET task_id = <string>$tid RETURN NONE;"
            + "COMMIT TRANSACTION;",
            new()
            {
                ["k"] = task.IdempotencyKey,
                ["tid"] = task.TaskId,
                ["sid"] = task.SessionId,
                ["n"] = task.Seq,
                ["expr"] = task.Expression,
                ["at"] = task.SubmittedAt,
                ["evt"] = task.EventJson,
                ["tp"] = task.Traceparent,
                ["pub"] = task.Published,
            },
            cancellationToken).ConfigureAwait(false);
        if (results.All(r => r.Ok))
        {
            return true;
        }

        if (results.Any(r => r.AlreadyExists))
        {
            return false;
        }

        throw new DatabaseUnavailableException($"creating task {task.TaskId} failed: {FirstError(results)}");
    }

    /// <inheritdoc/>
    public Task MarkTaskPublishedAsync(string taskId, CancellationToken cancellationToken) =>
        QueryAsync(
            "UPDATE type::record('task', <string>$tid) SET published = true RETURN NONE;",
            new() { ["tid"] = taskId },
            cancellationToken);

    /// <inheritdoc/>
    public async Task<bool> PingAsync(CancellationToken cancellationToken)
    {
        try
        {
            var results = await _client.QueryAsync("RETURN 1;", [], cancellationToken).ConfigureAwait(false);
            return results.Count == 1 && results[0].Ok;
        }
        catch (DatabaseUnavailableException)
        {
            return false;
        }
    }

    /// <summary>Converts a <c>key_press</c> row.</summary>
    /// <remarks><para><b>Description:</b> maps snake_case columns to the record.</para>
    /// <para><b>Business Justification:</b> typed access to stored presses.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="row">Row selected with <see cref="KeyPressColumns"/>.</param>
    /// <returns>The record.</returns>
    private static KeyPressRecord ToKeyPress(JsonObject row) => new(
        row["session_id"]!.GetValue<string>(),
        row["seq"]!.GetValue<long>(),
        row["key"]!.GetValue<string>(),
        Timestamp(row["received_at"]!.GetValue<string>()),
        row["event"]!.GetValue<string>(),
        row["traceparent"]!.GetValue<string>(),
        row["published"]!.GetValue<bool>(),
        row["task_id"]?.GetValue<string>());

    /// <summary>Converts a <c>task</c> row.</summary>
    /// <remarks><para><b>Description:</b> maps snake_case columns to the record.</para>
    /// <para><b>Business Justification:</b> typed access to stored tasks.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="row">Row selected with <see cref="TaskColumns"/>.</param>
    /// <returns>The record.</returns>
    private static TaskRecord ToTask(JsonObject row) => new(
        row["task_id"]!.GetValue<string>(),
        row["session_id"]!.GetValue<string>(),
        row["seq"]!.GetValue<long>(),
        row["expression"]!.GetValue<string>(),
        row["idempotency_key"]!.GetValue<string>(),
        Timestamp(row["submitted_at"]!.GetValue<string>()),
        row["event"]!.GetValue<string>(),
        row["traceparent"]!.GetValue<string>(),
        row["published"]!.GetValue<bool>());

    /// <summary>Normalises a datetime read from SurrealDB to the contract form.</summary>
    /// <remarks><para><b>Description:</b> SurrealDB renders datetimes with as many
    /// fractional digits as needed (none for whole seconds); the records use exactly
    /// three, like the events (ADR-0013).</para>
    /// <para><b>Business Justification:</b> one timestamp form everywhere.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="value">RFC 3339 datetime text.</param>
    /// <returns>The timestamp as <c>YYYY-MM-DDTHH:MM:SS.sssZ</c>.</returns>
    /// <exception cref="FormatException">The text is not a datetime.</exception>
    private static string Timestamp(string value) =>
        Events.EventFactory.FormatTimestamp(DateTimeOffset.Parse(value, System.Globalization.CultureInfo.InvariantCulture));

    /// <summary>Interprets the result of a <c>CREATE</c>.</summary>
    /// <remarks><para><b>Description:</b> success is true, <c>AlreadyExists</c> is false,
    /// any other error is raised.</para>
    /// <para><b>Business Justification:</b> idempotent creates.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="result">Result of the statement.</param>
    /// <returns>True when created, false when it already existed.</returns>
    /// <exception cref="DatabaseUnavailableException">Any other failure.</exception>
    private static bool CreatedOrExisting(StatementResult result) => result switch
    {
        { Ok: true } => true,
        { AlreadyExists: true } => false,
        _ => throw new DatabaseUnavailableException($"SurrealDB statement failed: {result.Result}"),
    };

    /// <summary>Returns the message of the first failed statement.</summary>
    /// <remarks><para><b>Description:</b> for error messages.</para>
    /// <para><b>Business Justification:</b> precise diagnostics.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(n).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="results">Statement results.</param>
    /// <returns>The first error message, or an empty string.</returns>
    private static string FirstError(IEnumerable<StatementResult> results) =>
        results.FirstOrDefault(r => !r.Ok)?.Result?.ToString() ?? string.Empty;

    /// <summary>Runs a query whose statements must all succeed.</summary>
    /// <remarks><para><b>Description:</b> raises on the first failed statement.</para>
    /// <para><b>Business Justification:</b> reads and updates have no expected failures.</para>
    /// <para><b>Side Effects:</b> database access as given by <paramref name="sql"/>.</para>
    /// <para><b>Complexity:</b> network bound.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="sql">Statements.</param>
    /// <param name="variables">Variables.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>The statement results.</returns>
    /// <exception cref="DatabaseUnavailableException">The request or a statement failed.</exception>
    private async Task<IReadOnlyList<StatementResult>> QueryAsync(
        string sql,
        Dictionary<string, object?> variables,
        CancellationToken cancellationToken)
    {
        var results = await _client.QueryAsync(sql, variables, cancellationToken).ConfigureAwait(false);
        if (results.Any(r => !r.Ok))
        {
            throw new DatabaseUnavailableException($"SurrealDB statement failed: {FirstError(results)}");
        }

        return results;
    }
}
