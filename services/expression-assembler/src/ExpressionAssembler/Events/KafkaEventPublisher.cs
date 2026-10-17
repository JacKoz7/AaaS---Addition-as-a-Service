// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Events.KafkaEventPublisher
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Publishes events to Redpanda through the Kafka API
//                  (Confluent.Kafka) and reports broker reachability for the
//                  health endpoint.
// Related Docs:    ADR-0011, ADR-0014, contracts/events/topics.psv,
//                  services/expression-assembler/docs/DEPENDENCIES.md

using System.Text;
using Confluent.Kafka;

namespace AaaS.ExpressionAssembler.Events;

/// <summary>Publishes events to the event bus.</summary>
/// <remarks>
/// <para><b>Description:</b> abstraction over the Kafka producer so that the key
/// handling logic can be tested without a broker.</para>
/// <para><b>Business Justification:</b> isolates the event bus, a shared dependency.</para>
/// <para><b>Thread Safety:</b> implementations must be safe for concurrent use.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>await publisher.PublishAsync(evt, ct);</code></example>
public interface IEventPublisher
{
    /// <summary>Publishes one event and waits for the broker acknowledgement.</summary>
    /// <remarks>
    /// <para><b>Description:</b> returns once every in-sync replica has the message.</para>
    /// <para><b>Business Justification:</b> a task is reported as accepted only after
    /// its event is durable.</para>
    /// <para><b>Side Effects:</b> one Kafka produce request.</para>
    /// <para><b>Complexity:</b> O(message size).</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="outgoing">The event to publish.</param>
    /// <param name="cancellationToken">Cancels the wait (the message may still be delivered).</param>
    /// <returns>A task that completes when the broker acknowledged the message.</returns>
    /// <exception cref="EventPublishException">The broker did not acknowledge the message in time.</exception>
    Task PublishAsync(OutgoingEvent outgoing, CancellationToken cancellationToken);

    /// <summary>Checks that the broker answers a metadata request.</summary>
    /// <remarks>
    /// <para><b>Description:</b> used by <c>GET /health</c>.</para>
    /// <para><b>Business Justification:</b> an assembler without a broker cannot start tasks.</para>
    /// <para><b>Side Effects:</b> one metadata request.</para>
    /// <para><b>Complexity:</b> O(number of topics).</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <returns>True when the broker answered within one second.</returns>
    bool IsBrokerReachable();
}

/// <summary>Raised when an event could not be published.</summary>
/// <remarks>
/// <para><b>Description:</b> wraps the producer error; the caller answers 503 and
/// the client retries the same request, which republishes the stored event.</para>
/// <para><b>Business Justification:</b> no task is reported as accepted unless its
/// event reached the bus.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>throw new EventPublishException("timed out", inner);</code></example>
public sealed class EventPublishException : Exception
{
    /// <summary>Initializes a new instance of the <see cref="EventPublishException"/> class.</summary>
    /// <remarks><para><b>Description:</b> standard exception constructor.</para>
    /// <para><b>Business Justification:</b> see the type documentation.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="message">Description of the failure.</param>
    /// <param name="innerException">The producer exception.</param>
    public EventPublishException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>Kafka producer for Redpanda.</summary>
/// <remarks>
/// <para><b>Description:</b> one idempotent producer per process
/// (<c>enable.idempotence=true</c>, <c>acks=all</c>), so broker-side retries never
/// duplicate a message. A broker request times out after 1 second and a message
/// after 1.5 seconds (librdkafka retries in between with backoff), so that a key
/// press is answered within the 1.8-second request budget, below the gateway's
/// 2-second timeout (ADR-0014). A message still in flight when the budget expires
/// may be delivered later; the retry of the client republishes the same event,
/// which consumers deduplicate. The <c>traceparent</c> is sent as a
/// message header as well as in the envelope.</para>
/// <para><b>Business Justification:</b> durable, ordered delivery of the events that
/// start every addition (CLAUDE.md 4.2, 6.1 timeouts and retries).</para>
/// <para><b>Thread Safety:</b> the Confluent producer is thread-safe; so is this class.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>using var publisher = new KafkaEventPublisher("redpanda:9092", "expression-assembler");</code></example>
public sealed class KafkaEventPublisher : IEventPublisher, IDisposable
{
    /// <summary>The underlying producer.</summary>
    /// <remarks><para><b>Description:</b> keys and values are UTF-8 strings.</para>
    /// <para><b>Business Justification:</b> JSON events keyed by task or session.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly IProducer<string, string> _producer;

    /// <summary>Admin client sharing the producer's connection, for metadata checks.</summary>
    /// <remarks><para><b>Description:</b> no extra broker connection is opened.</para>
    /// <para><b>Business Justification:</b> health checks without extra load.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly IAdminClient _admin;

    /// <summary>Initializes a new instance of the <see cref="KafkaEventPublisher"/> class.</summary>
    /// <remarks>
    /// <para><b>Description:</b> creates the producer; the connection is established lazily.</para>
    /// <para><b>Business Justification:</b> see the type documentation.</para>
    /// <para><b>Side Effects:</b> starts librdkafka background threads.</para>
    /// <para><b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para>
    /// </remarks>
    /// <param name="bootstrapServers">Comma-separated <c>host:port</c> list.</param>
    /// <param name="clientId">Client identifier shown in broker logs and Redpanda Console.</param>
    public KafkaEventPublisher(string bootstrapServers, string clientId)
    {
        var config = new ProducerConfig
        {
            BootstrapServers = bootstrapServers,
            ClientId = clientId,
            Acks = Acks.All,
            EnableIdempotence = true,
            RequestTimeoutMs = 1000,
            MessageTimeoutMs = 1500,
            RetryBackoffMs = 100,
            RetryBackoffMaxMs = 1000,
            LingerMs = 0,
        };
        _producer = new ProducerBuilder<string, string>(config).Build();
        _admin = new DependentAdminClientBuilder(_producer.Handle).Build();
    }

    /// <inheritdoc/>
    /// <remarks>
    /// <para><b>Description:</b> produces with the event's key and a
    /// <c>traceparent</c> header and awaits the delivery report.</para>
    /// <para><b>Business Justification:</b> see <see cref="IEventPublisher.PublishAsync"/>.</para>
    /// <para><b>Side Effects:</b> one Kafka produce request.</para>
    /// <para><b>Complexity:</b> O(message size).</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para>
    /// </remarks>
    public async Task PublishAsync(OutgoingEvent outgoing, CancellationToken cancellationToken)
    {
        var message = new Message<string, string>
        {
            Key = outgoing.Key,
            Value = outgoing.Json,
            Headers = new Headers { { "traceparent", Encoding.ASCII.GetBytes(outgoing.Traceparent) } },
        };
        try
        {
            await _producer.ProduceAsync(outgoing.Topic, message, cancellationToken).ConfigureAwait(false);
        }
        catch (ProduceException<string, string> error)
        {
            throw new EventPublishException($"publishing to {outgoing.Topic} failed: {error.Error.Reason}", error);
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    /// <para><b>Description:</b> requests metadata of all topics with a one-second timeout.</para>
    /// <para><b>Business Justification:</b> see <see cref="IEventPublisher.IsBrokerReachable"/>.</para>
    /// <para><b>Side Effects:</b> one metadata request.</para>
    /// <para><b>Complexity:</b> O(number of topics).</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para>
    /// </remarks>
    public bool IsBrokerReachable()
    {
        try
        {
            return _admin.GetMetadata(TimeSpan.FromSeconds(1)).Brokers.Count > 0;
        }
        catch (KafkaException)
        {
            return false;
        }
    }

    /// <summary>Flushes pending messages (up to 5 seconds) and releases the producer.</summary>
    /// <remarks>
    /// <para><b>Description:</b> called on graceful shutdown, within the 10-second budget
    /// of CLAUDE.md 6.1.</para>
    /// <para><b>Business Justification:</b> no acknowledged request loses its event on shutdown.</para>
    /// <para><b>Side Effects:</b> network flush; stops librdkafka threads.</para>
    /// <para><b>Complexity:</b> O(pending messages).</para>
    /// <para><b>Thread Safety:</b> call once, after the server stopped accepting requests.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para>
    /// </remarks>
    public void Dispose()
    {
        _producer.Flush(TimeSpan.FromSeconds(5));
        _admin.Dispose();
        _producer.Dispose();
    }
}
