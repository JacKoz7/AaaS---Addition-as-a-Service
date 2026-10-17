// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Events.EventFactory
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Builds the events the service publishes
//                  (aaas.key.pressed.v1, aaas.expression.submitted.v1) in the
//                  envelope of CLAUDE.md 4.2 and serializes them to JSON.
// Related Docs:    contracts/events/envelope.v1.schema.json,
//                  contracts/events/aaas.key.pressed.v1.schema.json,
//                  contracts/events/aaas.expression.submitted.v1.schema.json,
//                  ADR-0013

using System.Diagnostics;
using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AaaS.ExpressionAssembler.Events;

/// <summary>An event ready to be published: topic, message key and JSON value.</summary>
/// <remarks>
/// <para><b>Description:</b> <paramref name="Json"/> is the complete envelope; it
/// is stored before publishing so that a retry publishes byte-identical content
/// with the same <c>eventId</c>.</para>
/// <para><b>Business Justification:</b> consumers deduplicate on <c>eventId</c>
/// (CLAUDE.md 4.2); identical retries make that deduplication sufficient.</para>
/// <para><b>Thread Safety:</b> immutable record; safe.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <param name="Topic">Topic name, for example <c>aaas.expression.submitted.v1</c>.</param>
/// <param name="Key">Message key: the <c>taskId</c>, or the session for events without a task.</param>
/// <param name="Json">Serialized envelope.</param>
/// <param name="Traceparent">W3C <c>traceparent</c> of the envelope, also sent as a message header.</param>
/// <example><code>await publisher.PublishAsync(new OutgoingEvent(topic, key, json, traceparent), ct);</code></example>
public sealed record OutgoingEvent(string Topic, string Key, string Json, string Traceparent);

/// <summary>Builds the envelopes of the events produced by expression-assembler.</summary>
/// <remarks>
/// <para><b>Description:</b> Fills <c>eventId</c> (UUIDv7), <c>occurredAt</c>
/// (UTC, three fractional digits, <c>Z</c>), <c>producer</c> and
/// <c>traceparent</c> as fixed by ADR-0013. The trace context is taken from the
/// current <see cref="Activity"/> (the incoming request span); without one, a new
/// random trace is started so that the envelope is always valid.</para>
/// <para><b>Business Justification:</b> every event must validate against its
/// contract (CLAUDE.md 4.2); one factory keeps all of them consistent.</para>
/// <para><b>Thread Safety:</b> immutable after construction; safe.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>var evt = new EventFactory("expression-assembler").ExpressionSubmitted(taskId, session, "2+3", now);</code></example>
/// <seealso cref="OutgoingEvent"/>
public sealed class EventFactory
{
    /// <summary>Topic of key press events.</summary>
    /// <remarks><para><b>Description:</b> registered in <c>contracts/events/topics.psv</c>.</para>
    /// <para><b>Business Justification:</b> audit of every click (CLAUDE.md 4.2).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public const string KeyPressedTopic = "aaas.key.pressed.v1";

    /// <summary>Topic of submitted expressions.</summary>
    /// <remarks><para><b>Description:</b> consumed by parser and stopwatch.</para>
    /// <para><b>Business Justification:</b> starts every addition (CLAUDE.md 3).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public const string ExpressionSubmittedTopic = "aaas.expression.submitted.v1";

    /// <summary>JSON options: no indentation, nulls written (the envelope requires <c>taskId</c>).</summary>
    /// <remarks><para><b>Description:</b> property names come from
    /// <see cref="JsonPropertyNameAttribute"/> on the envelope types. The relaxed
    /// encoder writes <c>+</c> literally instead of <c>\u002B</c>; events are never
    /// embedded in HTML, so HTML-sensitive escaping is not needed.</para>
    /// <para><b>Business Justification:</b> compact, contract-exact messages.</para>
    /// <para><b>Thread Safety:</b> immutable once used; safe.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = false,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    /// <summary>Value of <c>producer</c> in every envelope.</summary>
    /// <remarks><para><b>Description:</b> the service name from configuration.</para>
    /// <para><b>Business Justification:</b> the contracts fix the producer of each topic.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly string _producer;

    /// <summary>Initializes a new instance of the <see cref="EventFactory"/> class.</summary>
    /// <remarks><para><b>Description:</b> stores the producer name.</para>
    /// <para><b>Business Justification:</b> see the type documentation.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="producer">Service name; must be <c>expression-assembler</c> for valid events.</param>
    public EventFactory(string producer) => _producer = producer;

    /// <summary>Formats an instant as the contract timestamp <c>YYYY-MM-DDTHH:MM:SS.sssZ</c>.</summary>
    /// <remarks>
    /// <para><b>Description:</b> converts to UTC and truncates to milliseconds.</para>
    /// <para><b>Business Justification:</b> ADR-0013 fixes this form for every timestamp.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="instant">Any instant.</param>
    /// <returns>The formatted UTC timestamp.</returns>
    /// <example><code>EventFactory.FormatTimestamp(DateTimeOffset.UnixEpoch) // "1970-01-01T00:00:00.000Z"</code></example>
    public static string FormatTimestamp(DateTimeOffset instant) =>
        instant.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);

    /// <summary>Returns the W3C <c>traceparent</c> of the current activity, or a new one.</summary>
    /// <remarks>
    /// <para><b>Description:</b> uses <see cref="Activity.Current"/> when it has a W3C
    /// identifier; otherwise creates random trace and span identifiers with the
    /// sampled flag.</para>
    /// <para><b>Business Justification:</b> one trace per addition (CLAUDE.md 6.1).</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <returns>A <c>traceparent</c> such as <c>00-4bf9…4736-00f0…02b7-01</c>.</returns>
    /// <example><code>var tp = EventFactory.CurrentTraceparent();</code></example>
    public static string CurrentTraceparent()
    {
        var activity = Activity.Current;
        if (activity is { IdFormat: ActivityIdFormat.W3C, Id: { } id })
        {
            return id;
        }

        return $"00-{ActivityTraceId.CreateRandom().ToHexString()}-{ActivitySpanId.CreateRandom().ToHexString()}-01";
    }

    /// <summary>Builds <c>aaas.key.pressed.v1</c> for one key press.</summary>
    /// <remarks>
    /// <para><b>Description:</b> <c>taskId</c> is null (no task exists for a key
    /// press); the message key is the session, so the presses of one session stay
    /// ordered in one partition.</para>
    /// <para><b>Business Justification:</b> audit trail of every click (CLAUDE.md 3, step 2).</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="sessionId">Lowercase UUID of the session.</param>
    /// <param name="key">Pressed key.</param>
    /// <param name="seq">Position of the press.</param>
    /// <param name="occurredAt">When the press was received.</param>
    /// <returns>The event to store and publish.</returns>
    /// <example><code>var evt = factory.KeyPressed(session, "7", 0, DateTimeOffset.UtcNow);</code></example>
    public OutgoingEvent KeyPressed(string sessionId, string key, long seq, DateTimeOffset occurredAt) =>
        Build(KeyPressedTopic, sessionId, null, occurredAt, new KeyPressedPayload(sessionId, key, seq));

    /// <summary>Builds <c>aaas.expression.submitted.v1</c> for a new task.</summary>
    /// <remarks>
    /// <para><b>Description:</b> the message key is the <c>taskId</c> (topics are
    /// partitioned by task, CLAUDE.md 4.2); <c>occurredAt</c> is the time of the
    /// <c>=</c> press, which stopwatch uses as the start of the official time.</para>
    /// <para><b>Business Justification:</b> starts the addition (CLAUDE.md 3, steps 2 and 3).</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(n) in the expression length.</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="taskId">Lowercase UUIDv7 of the new task.</param>
    /// <param name="sessionId">Lowercase UUID of the session.</param>
    /// <param name="expression">Expression from <see cref="Keys.ExpressionBuilder"/>.</param>
    /// <param name="occurredAt">When <c>=</c> was pressed.</param>
    /// <returns>The event to store and publish.</returns>
    /// <example><code>var evt = factory.ExpressionSubmitted(taskId, session, "2+3", DateTimeOffset.UtcNow);</code></example>
    public OutgoingEvent ExpressionSubmitted(string taskId, string sessionId, string expression, DateTimeOffset occurredAt) =>
        Build(ExpressionSubmittedTopic, taskId, taskId, occurredAt, new ExpressionSubmittedPayload(sessionId, expression));

    /// <summary>Wraps a payload in the envelope and serializes it.</summary>
    /// <remarks>
    /// <para><b>Description:</b> derives <c>type</c> and <c>version</c> from the
    /// topic name (<c>&lt;type&gt;.v&lt;version&gt;</c>).</para>
    /// <para><b>Business Justification:</b> one place builds every envelope.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(size of the payload).</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="topic">Topic name ending in <c>.v&lt;N&gt;</c>.</param>
    /// <param name="key">Message key.</param>
    /// <param name="taskId">Task of the event, or null.</param>
    /// <param name="occurredAt">Instant of the event.</param>
    /// <param name="payload">Payload object serialized with its runtime type.</param>
    /// <returns>The event with its JSON.</returns>
    private OutgoingEvent Build(string topic, string key, string? taskId, DateTimeOffset occurredAt, object payload)
    {
        var dot = topic.LastIndexOf(".v", StringComparison.Ordinal);
        var traceparent = CurrentTraceparent();
        var envelope = new EventEnvelope(
            Guid.CreateVersion7(occurredAt).ToString("D"),
            topic[..dot],
            int.Parse(topic[(dot + 2)..], CultureInfo.InvariantCulture),
            FormatTimestamp(occurredAt),
            _producer,
            taskId,
            traceparent,
            payload);
        return new OutgoingEvent(topic, key, JsonSerializer.Serialize(envelope, JsonOptions), traceparent);
    }
}

/// <summary>The event envelope of CLAUDE.md 4.2.</summary>
/// <remarks>
/// <para><b>Description:</b> property order follows the contract; <c>taskId</c> is
/// serialized as <c>null</c> when absent because the envelope requires it.</para>
/// <para><b>Business Justification:</b> the shared contract of every event.</para>
/// <para><b>Thread Safety:</b> immutable record; safe.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <param name="EventId">UUIDv7 of the event.</param>
/// <param name="Type">Topic name without the version suffix.</param>
/// <param name="Version">Major version of the event.</param>
/// <param name="OccurredAt">Contract timestamp.</param>
/// <param name="Producer">Producing service.</param>
/// <param name="TaskId">Task, or null for events without one.</param>
/// <param name="Traceparent">W3C trace context.</param>
/// <param name="Payload">Type-specific content.</param>
internal sealed record EventEnvelope(
    [property: JsonPropertyName("eventId")] string EventId,
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("occurredAt")] string OccurredAt,
    [property: JsonPropertyName("producer")] string Producer,
    [property: JsonPropertyName("taskId")] string? TaskId,
    [property: JsonPropertyName("traceparent")] string Traceparent,
    [property: JsonPropertyName("payload")] object Payload);

/// <summary>Payload of <c>aaas.key.pressed.v1</c>.</summary>
/// <remarks>
/// <para><b>Description:</b> the validated key press.</para>
/// <para><b>Business Justification:</b> audit of every click.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <param name="SessionId">Lowercase UUID of the session.</param>
/// <param name="Key">Pressed key.</param>
/// <param name="Seq">Position of the press.</param>
internal sealed record KeyPressedPayload(
    [property: JsonPropertyName("sessionId")] string SessionId,
    [property: JsonPropertyName("key")] string Key,
    [property: JsonPropertyName("seq")] long Seq);

/// <summary>Payload of <c>aaas.expression.submitted.v1</c>.</summary>
/// <remarks>
/// <para><b>Description:</b> the assembled expression and its session.</para>
/// <para><b>Business Justification:</b> the input of the parser.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <param name="SessionId">Lowercase UUID of the session.</param>
/// <param name="Expression">Digit and <c>+</c> keys typed before <c>=</c>.</param>
internal sealed record ExpressionSubmittedPayload(
    [property: JsonPropertyName("sessionId")] string SessionId,
    [property: JsonPropertyName("expression")] string Expression);
