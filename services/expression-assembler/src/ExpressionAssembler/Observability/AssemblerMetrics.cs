// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Observability.AssemblerMetrics
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Prometheus metrics of the service, prefixed with the
//                  service name (expression_assembler_*), served on /metrics.
// Related Docs:    services/expression-assembler/docs/SLO.md,
//                  services/expression-assembler/docs/RUNBOOK.md, CLAUDE.md 6.1

using Prometheus;

namespace AaaS.ExpressionAssembler.Observability;

/// <summary>Business metrics of expression-assembler.</summary>
/// <remarks>
/// <para><b>Description:</b> counters registered in the default Prometheus registry
/// and exported by <c>GET /metrics</c> next to the HTTP metrics of prometheus-net
/// (<c>http_requests_received_total</c>, <c>http_request_duration_seconds</c>).</para>
/// <para><b>Business Justification:</b> the SLIs of SLO.md and the alerts of P7.4
/// are computed from these series.</para>
/// <para><b>Thread Safety:</b> prometheus-net counters are thread-safe.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>AssemblerMetrics.KeyPresses.WithLabels("7").Inc();</code></example>
public static class AssemblerMetrics
{
    /// <summary>Gets the counter of newly recorded key presses, by key.</summary>
    /// <remarks><para><b>Description:</b> <c>expression_assembler_key_presses_total{key}</c>;
    /// retries of an already recorded press are not counted.</para>
    /// <para><b>Business Justification:</b> input volume.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public static Counter KeyPresses { get; } = Metrics.CreateCounter(
        "expression_assembler_key_presses_total", "Key presses recorded for the first time.", "key");

    /// <summary>Gets the counter of created tasks.</summary>
    /// <remarks><para><b>Description:</b> <c>expression_assembler_tasks_submitted_total</c>;
    /// one per accepted <c>Idempotency-Key</c>.</para>
    /// <para><b>Business Justification:</b> additions started.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public static Counter TasksSubmitted { get; } = Metrics.CreateCounter(
        "expression_assembler_tasks_submitted_total", "Tasks created by the = key.");

    /// <summary>Gets the counter of rejected requests, by reason.</summary>
    /// <remarks><para><b>Description:</b> <c>expression_assembler_rejected_total{reason}</c>
    /// with reason <c>invalid</c> (400), <c>conflict</c> (409), <c>expression</c> (422),
    /// <c>database</c>, <c>broker</c> or <c>deadline</c> (503).</para>
    /// <para><b>Business Justification:</b> error budget of SLO.md.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public static Counter Rejected { get; } = Metrics.CreateCounter(
        "expression_assembler_rejected_total", "Key presses answered with a problem.", "reason");

    /// <summary>Gets the counter of publication attempts, by topic and outcome.</summary>
    /// <remarks><para><b>Description:</b> <c>expression_assembler_events_published_total{topic,outcome}</c>,
    /// outcome <c>ok</c> or <c>error</c>.</para>
    /// <para><b>Business Justification:</b> health of the event bus as seen by the producer.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public static Counter EventsPublished { get; } = Metrics.CreateCounter(
        "expression_assembler_events_published_total", "Event publication attempts.", "topic", "outcome");
}
