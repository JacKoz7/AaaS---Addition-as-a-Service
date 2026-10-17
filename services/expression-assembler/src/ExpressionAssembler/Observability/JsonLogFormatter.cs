// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Observability.JsonLogFormatter
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Console formatter writing one JSON object per log entry
//                  with the fields of CLAUDE.md 6.1: ts, level, service, msg,
//                  taskId, traceId, spanId.
// Related Docs:    CLAUDE.md 6.1, services/expression-assembler/docs/RUNBOOK.md

using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Logging.Console;

namespace AaaS.ExpressionAssembler.Observability;

/// <summary>Structured JSON log formatter.</summary>
/// <remarks>
/// <para><b>Description:</b> every entry is one line:
/// <c>{"ts","level","service","msg","taskId","traceId","spanId","logger"}</c> and, when
/// present, <c>"error"</c> with the exception text. <c>taskId</c> comes from a
/// <c>TaskId</c> value in the message state or in any logging scope; <c>traceId</c> and
/// <c>spanId</c> come from the current <see cref="Activity"/>. Missing values are
/// written as null so that every line has the same fields.</para>
/// <para><b>Business Justification:</b> CLAUDE.md 6.1 requires structured logs that Loki
/// (P7.1) can query by task and trace.</para>
/// <para><b>Thread Safety:</b> safe; the console logger serialises writes.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>builder.Logging.AddConsole(o =&gt; o.FormatterName = JsonLogFormatter.FormatterName)
///     .AddConsoleFormatter&lt;JsonLogFormatter, ConsoleFormatterOptions&gt;();</code></example>
public sealed class JsonLogFormatter : ConsoleFormatter
{
    /// <summary>Name under which the formatter is registered.</summary>
    /// <remarks><para><b>Description:</b> referenced by the console logger options.</para>
    /// <para><b>Business Justification:</b> selects this formatter.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public const string FormatterName = "aaas-json";

    /// <summary>Service name written in every entry.</summary>
    /// <remarks><para><b>Description:</b> from <c>AAAS_SERVICE</c>.</para>
    /// <para><b>Business Justification:</b> filter logs by service.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly string _service;

    /// <summary>Initializes a new instance of the <see cref="JsonLogFormatter"/> class.</summary>
    /// <remarks><para><b>Description:</b> reads the service name from the environment.</para>
    /// <para><b>Business Justification:</b> see the type documentation.</para>
    /// <para><b>Side Effects:</b> reads one environment variable. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public JsonLogFormatter()
        : base(FormatterName) =>
        _service = Environment.GetEnvironmentVariable("AAAS_SERVICE") ?? "expression-assembler";

    /// <summary>Writes one log entry as a JSON line.</summary>
    /// <remarks>
    /// <para><b>Description:</b> see the type documentation.</para>
    /// <para><b>Business Justification:</b> structured logs.</para>
    /// <para><b>Side Effects:</b> writes to <paramref name="textWriter"/>.</para>
    /// <para><b>Complexity:</b> O(message size + number of scopes).</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <typeparam name="TState">Type of the log state.</typeparam>
    /// <param name="logEntry">The entry.</param>
    /// <param name="scopeProvider">Active scopes, or null.</param>
    /// <param name="textWriter">Destination.</param>
    public override void Write<TState>(in LogEntry<TState> logEntry, IExternalScopeProvider? scopeProvider, TextWriter textWriter)
    {
        var message = logEntry.Formatter(logEntry.State, logEntry.Exception);
        string? taskId = FindTaskId(logEntry.State);
        scopeProvider?.ForEachScope((scope, _) => taskId ??= FindTaskId(scope), (object?)null);
        var activity = Activity.Current;

        using var buffer = new MemoryStream();
        using (var json = new Utf8JsonWriter(buffer))
        {
            json.WriteStartObject();
            json.WriteString("ts", DateTimeOffset.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture));
            json.WriteString("level", LevelName(logEntry.LogLevel));
            json.WriteString("service", _service);
            json.WriteString("msg", message);
            json.WriteString("taskId", taskId);
            json.WriteString("traceId", activity?.TraceId.ToHexString());
            json.WriteString("spanId", activity?.SpanId.ToHexString());
            json.WriteString("logger", logEntry.Category);
            if (logEntry.Exception is not null)
            {
                json.WriteString("error", logEntry.Exception.ToString());
            }

            json.WriteEndObject();
        }

        textWriter.WriteLine(System.Text.Encoding.UTF8.GetString(buffer.ToArray()));
    }

    /// <summary>Maps a log level to its short lowercase name.</summary>
    /// <remarks><para><b>Description:</b> trace, debug, info, warn, error, fatal.</para>
    /// <para><b>Business Justification:</b> one level vocabulary across 28 languages.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="level">.NET log level.</param>
    /// <returns>The short name.</returns>
    /// <example><code>LevelName(LogLevel.Warning) // "warn"</code></example>
    internal static string LevelName(LogLevel level) => level switch
    {
        LogLevel.Trace => "trace",
        LogLevel.Debug => "debug",
        LogLevel.Information => "info",
        LogLevel.Warning => "warn",
        LogLevel.Error => "error",
        LogLevel.Critical => "fatal",
        _ => "none",
    };

    /// <summary>Extracts a <c>TaskId</c> value from log state or a scope.</summary>
    /// <remarks><para><b>Description:</b> structured state is a list of key/value pairs;
    /// the key comparison is case-insensitive.</para>
    /// <para><b>Business Justification:</b> correlate logs with a task.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(number of values).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="state">Log state or scope object.</param>
    /// <returns>The task identifier, or null.</returns>
    internal static string? FindTaskId(object? state) =>
        state is IEnumerable<KeyValuePair<string, object?>> values
            ? values.FirstOrDefault(v => string.Equals(v.Key, "TaskId", StringComparison.OrdinalIgnoreCase)).Value?.ToString()
            : null;
}
