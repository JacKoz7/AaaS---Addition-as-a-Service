// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Program
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Entry point: reads the configuration, applies the
//                  database migrations, and serves POST /api/v1/keys,
//                  GET /health and GET /metrics on port 8080 with JSON logs,
//                  tracing and graceful shutdown.
// Related Docs:    services/expression-assembler/README.md,
//                  services/expression-assembler/docs/API.md, CLAUDE.md 4.1, 6.1

using System.Text.Json;
using AaaS.ExpressionAssembler.Events;
using AaaS.ExpressionAssembler.Keys;
using AaaS.ExpressionAssembler.Observability;
using AaaS.ExpressionAssembler.Storage;
using Microsoft.Extensions.Logging.Console;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Prometheus;

namespace AaaS.ExpressionAssembler;

/// <summary>Entry point and composition root of expression-assembler.</summary>
/// <remarks>
/// <para><b>Description:</b> <see cref="Main"/> reads <see cref="AssemblerOptions"/>,
/// builds the application with <see cref="CreateApp"/>, applies the migrations
/// (retrying while the database starts) and runs the server. A configuration or
/// migration failure ends the process with exit code 1 so that Compose reports the
/// container as unhealthy instead of serving without a schema.</para>
/// <para><b>Business Justification:</b> the first service of the addition flow
/// (CLAUDE.md 3, step 2) must either work completely or not start.</para>
/// <para><b>Thread Safety:</b> not applicable (process entry point).</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>docker compose up expression-assembler</code></example>
public static partial class Program
{
    /// <summary>Path of the key press endpoint (CLAUDE.md 4.1).</summary>
    /// <remarks><para><b>Description:</b> routed by the gateway from <c>/api/v1/keys</c>
    /// unchanged.</para>
    /// <para><b>Business Justification:</b> public API contract.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public const string KeysPath = "/api/v1/keys";

    /// <summary>Largest accepted request body, in bytes.</summary>
    /// <remarks><para><b>Description:</b> a key press body is under 100 bytes; 4 KiB
    /// leaves room for whitespace while bounding memory per request.</para>
    /// <para><b>Business Justification:</b> denial-of-service mitigation (THREAT_MODEL.md).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public const long MaxBodyBytes = 4096;

    /// <summary>Time budget of one key press request.</summary>
    /// <remarks><para><b>Description:</b> 1.8 seconds, below the 2-second response
    /// timeout of the gateway (ADR-0012), so that a slow dependency is answered with
    /// this service's 503 problem instead of the gateway's 504. Every database query and
    /// publication of the request shares the budget (ADR-0014).</para>
    /// <para><b>Business Justification:</b> precise errors and a bounded wait per click.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public static readonly TimeSpan RequestBudget = TimeSpan.FromMilliseconds(1800);

    /// <summary>Starts the service.</summary>
    /// <remarks>
    /// <para><b>Description:</b> see the type documentation.</para>
    /// <para><b>Business Justification:</b> process entry point.</para>
    /// <para><b>Side Effects:</b> reads the environment; creates the Kafka producer;
    /// applies the migrations; listens on the HTTP port until SIGTERM.</para>
    /// <para><b>Complexity:</b> runs until shutdown.</para>
    /// <para><b>Thread Safety:</b> not applicable.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="args">Command-line arguments passed to the host.</param>
    /// <returns>0 after a graceful shutdown; 1 on a configuration or migration failure.</returns>
    public static async Task<int> Main(string[] args)
    {
        AssemblerOptions options;
        try
        {
            options = AssemblerOptions.FromEnvironment(Environment.GetEnvironmentVariable);
        }
        catch (InvalidOperationException error)
        {
            await Console.Error.WriteLineAsync($"expression-assembler: invalid configuration: {error.Message}").ConfigureAwait(false);
            return 1;
        }

        await using var app = CreateApp(options, args);
        var logger = app.Services.GetRequiredService<ILogger<MigrationRunner>>();

        // Create the Kafka producer now, so that a missing native library or an
        // invalid configuration stops the process instead of failing requests.
        app.Services.GetRequiredService<IEventPublisher>();
        var runner = app.Services.GetRequiredService<MigrationRunner>();
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                var applied = await runner.RunAsync(app.Lifetime.ApplicationStopping).ConfigureAwait(false);
                LogMigrationsDone(logger, applied);
                break;
            }
            catch (DatabaseUnavailableException error) when (attempt < 15)
            {
                LogMigrationRetry(logger, attempt, error.Message);
                await Task.Delay(TimeSpan.FromSeconds(2), app.Lifetime.ApplicationStopping).ConfigureAwait(false);
            }
            catch (Exception error) when (error is DatabaseUnavailableException or InvalidOperationException)
            {
                LogMigrationFailed(logger, error);
                return 1;
            }
        }

        await app.RunAsync().ConfigureAwait(false);
        return 0;
    }

    /// <summary>Builds the web application.</summary>
    /// <remarks>
    /// <para><b>Description:</b> registers configuration, the SurrealDB client (500 ms
    /// attempt timeout, three attempts with jitter, circuit breaker), the store, the
    /// Kafka publisher, the key service, JSON logging, Prometheus metrics, OpenTelemetry
    /// tracing (OTLP export only when <c>OTEL_EXPORTER_OTLP_ENDPOINT</c> is set; the
    /// collector arrives in P7.1) and an 8-second shutdown timeout; maps the endpoints.
    /// Tests pass <paramref name="configureServices"/> to replace the store and the
    /// publisher, and <paramref name="configureHost"/> to use an in-memory server.</para>
    /// <para><b>Business Justification:</b> one composition root for production and tests.</para>
    /// <para><b>Side Effects:</b> None until the application is started.</para>
    /// <para><b>Complexity:</b> O(1).</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="options">Validated configuration.</param>
    /// <param name="args">Command-line arguments.</param>
    /// <param name="configureServices">Optional service overrides, applied last.</param>
    /// <param name="configureHost">Optional web host configuration, for example a test server.</param>
    /// <returns>The application, not yet started.</returns>
    /// <example><code>var app = Program.CreateApp(options, [], s =&gt; s.AddSingleton&lt;IEventPublisher&gt;(fake));</code></example>
    public static WebApplication CreateApp(
        AssemblerOptions options,
        string[] args,
        Action<IServiceCollection>? configureServices = null,
        Action<IWebHostBuilder>? configureHost = null)
    {
        var builder = WebApplication.CreateSlimBuilder(args);
        builder.WebHost.ConfigureKestrel(kestrel =>
        {
            kestrel.ListenAnyIP(options.HttpPort);
            kestrel.Limits.MaxRequestBodySize = MaxBodyBytes;
            kestrel.AddServerHeader = false;
        });
        configureHost?.Invoke(builder.WebHost);
        builder.Services.Configure<HostOptions>(host => host.ShutdownTimeout = TimeSpan.FromSeconds(8));

        builder.Logging.ClearProviders();
        builder.Logging.AddConsole(console => console.FormatterName = JsonLogFormatter.FormatterName)
            .AddConsoleFormatter<JsonLogFormatter, ConsoleFormatterOptions>();
        builder.Logging.AddFilter("Microsoft.AspNetCore", LogLevel.Warning);
        builder.Logging.AddFilter("System.Net.Http.HttpClient", LogLevel.Warning);
        builder.Logging.AddFilter("Polly", LogLevel.Warning);

        builder.Services.AddSingleton(options);
        builder.Services.AddSingleton(TimeProvider.System);
        builder.Services.AddSingleton(new EventFactory(options.ServiceName));
        builder.Services.AddHttpClient<SurrealClient>(http => http.BaseAddress = options.DatabaseUrl)
            .AddStandardResilienceHandler(resilience =>
            {
                // Shorter than the 2 s default of CLAUDE.md 6.1: a request makes up to
                // six queries within RequestBudget (ADR-0014). Queries take 1-20 ms.
                resilience.AttemptTimeout.Timeout = TimeSpan.FromMilliseconds(500);
                resilience.Retry.MaxRetryAttempts = 2;
                resilience.Retry.UseJitter = true;
                resilience.Retry.Delay = TimeSpan.FromMilliseconds(50);
                resilience.TotalRequestTimeout.Timeout = TimeSpan.FromMilliseconds(1700);
                resilience.CircuitBreaker.SamplingDuration = TimeSpan.FromSeconds(10);
            });
        builder.Services.AddSingleton<IAssemblerStore>(sp => new SurrealAssemblerStore(sp.GetRequiredService<SurrealClient>()));
        builder.Services.AddSingleton<MigrationRunner>(sp => new MigrationRunner(
            sp.GetRequiredService<SurrealClient>(), options, sp.GetRequiredService<ILogger<MigrationRunner>>()));
        builder.Services.AddSingleton<IEventPublisher>(_ => new KafkaEventPublisher(options.KafkaBrokers, options.ServiceName));
        builder.Services.AddSingleton<KeyService>();
        builder.Services.AddOpenTelemetry()
            .ConfigureResource(resource => resource.AddService(options.ServiceName, serviceVersion: "0.1.0"))
            .WithTracing(tracing =>
            {
                tracing.AddAspNetCoreInstrumentation(aspnet => aspnet.Filter = context =>
                    context.Request.Path != "/health" && context.Request.Path != "/metrics");
                if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT")))
                {
                    tracing.AddOtlpExporter();
                }
            });
        configureServices?.Invoke(builder.Services);

        var app = builder.Build();
        app.UseHttpMetrics();
        app.MapPost(KeysPath, HandleKeyAsync);
        app.MapMethods(KeysPath, ["GET", "PUT", "PATCH", "DELETE"], (HttpContext context) =>
        {
            context.Response.Headers.Allow = "POST";
            return Results.Problem(
                statusCode: 405, title: "Method Not Allowed", detail: $"{KeysPath} accepts POST only", instance: KeysPath);
        });
        app.MapGet("/health", HandleHealthAsync);
        app.MapMetrics("/metrics");
        app.MapFallback((HttpContext context) => Results.Problem(
            statusCode: 404, title: "Not Found", detail: $"no endpoint at {context.Request.Path}", instance: context.Request.Path));
        return app;
    }

    /// <summary>Handles <c>POST /api/v1/keys</c>.</summary>
    /// <remarks>
    /// <para><b>Description:</b> deserializes the body leniently (malformed JSON becomes a
    /// 400 problem instead of a framework error), delegates to <see cref="KeyService"/>
    /// within <see cref="RequestBudget"/>
    /// and renders 204, 202 <c>{ taskId }</c> or an RFC 9457 problem.</para>
    /// <para><b>Business Justification:</b> CLAUDE.md 4.1.</para>
    /// <para><b>Side Effects:</b> those of <see cref="KeyService.HandleAsync"/>; logs
    /// accepted tasks.</para>
    /// <para><b>Complexity:</b> as <see cref="KeyService.HandleAsync"/>.</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="context">HTTP context.</param>
    /// <param name="service">Key service.</param>
    /// <param name="logger">Logger.</param>
    /// <returns>The HTTP result.</returns>
    internal static async Task<IResult> HandleKeyAsync(HttpContext context, KeyService service, ILogger<KeyService> logger)
    {
        KeyPressRequest? request;
        try
        {
            request = await JsonSerializer.DeserializeAsync<KeyPressRequest>(context.Request.Body, cancellationToken: context.RequestAborted)
                .ConfigureAwait(false);
        }
        catch (Exception error) when (error is JsonException or BadHttpRequestException)
        {
            request = null;
        }

        var idempotencyKey = context.Request.Headers["Idempotency-Key"].FirstOrDefault();
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
        budget.CancelAfter(RequestBudget);
        var result = await service.HandleAsync(request, idempotencyKey, budget.Token).ConfigureAwait(false);
        switch (result.Status)
        {
            case 202:
                using (logger.BeginScope(new Dictionary<string, object?> { ["TaskId"] = result.TaskId }))
                {
                    LogTaskAccepted(logger, result.TaskId!);
                }

                return Results.Json(new { taskId = result.TaskId }, statusCode: 202);
            case 204:
                return Results.NoContent();
        }

        return Results.Problem(statusCode: result.Status, title: result.Title, detail: result.Detail, instance: KeysPath);
    }

    /// <summary>Handles <c>GET /health</c> (liveness and readiness).</summary>
    /// <remarks>
    /// <para><b>Description:</b> answers <c>{"status":"ok","checks":{"database":"ok","broker":"ok"}}</c>
    /// with 200 when SurrealDB answers a query and Redpanda answers a metadata request;
    /// otherwise <c>status</c> is <c>"error"</c>, the failing check is <c>"error"</c> and the
    /// status code is 503.</para>
    /// <para><b>Business Justification:</b> CLAUDE.md 6.1; Compose waits for it.</para>
    /// <para><b>Side Effects:</b> one database query and one metadata request.</para>
    /// <para><b>Complexity:</b> network bound, at most about 3 seconds.</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="store">Store to ping.</param>
    /// <param name="publisher">Publisher whose broker is checked.</param>
    /// <param name="cancellationToken">Request cancellation.</param>
    /// <returns>The health document.</returns>
    internal static async Task<IResult> HandleHealthAsync(IAssemblerStore store, IEventPublisher publisher, CancellationToken cancellationToken)
    {
        var database = await store.PingAsync(cancellationToken).ConfigureAwait(false);
        var broker = await Task.Run(publisher.IsBrokerReachable, cancellationToken).ConfigureAwait(false);
        var healthy = database && broker;
        return Results.Json(
            new
            {
                status = healthy ? "ok" : "error",
                checks = new { database = database ? "ok" : "error", broker = broker ? "ok" : "error" },
            },
            statusCode: healthy ? 200 : 503);
    }

    /// <summary>Logs an accepted task.</summary>
    /// <remarks><para><b>Description:</b> source-generated; the task is also in the scope.</para>
    /// <para><b>Business Justification:</b> the first log line of every addition.</para>
    /// <para><b>Side Effects:</b> one log line. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="logger">Logger.</param>
    /// <param name="taskId">Accepted task.</param>
    [LoggerMessage(Level = LogLevel.Information, Message = "task {TaskId} accepted")]
    private static partial void LogTaskAccepted(ILogger logger, string taskId);

    /// <summary>Logs the end of the migration run.</summary>
    /// <remarks><para><b>Description:</b> source-generated.</para>
    /// <para><b>Business Justification:</b> startup audit.</para>
    /// <para><b>Side Effects:</b> one log line. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="logger">Logger.</param>
    /// <param name="applied">Number of migrations applied.</param>
    [LoggerMessage(Level = LogLevel.Information, Message = "database schema up to date ({Applied} migrations applied)")]
    private static partial void LogMigrationsDone(ILogger logger, int applied);

    /// <summary>Logs a retried migration attempt.</summary>
    /// <remarks><para><b>Description:</b> source-generated warning.</para>
    /// <para><b>Business Justification:</b> the database may still be starting.</para>
    /// <para><b>Side Effects:</b> one log line. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="logger">Logger.</param>
    /// <param name="attempt">Failed attempt number.</param>
    /// <param name="reason">Failure message.</param>
    [LoggerMessage(Level = LogLevel.Warning, Message = "database not ready (attempt {Attempt}): {Reason}")]
    private static partial void LogMigrationRetry(ILogger logger, int attempt, string reason);

    /// <summary>Logs a fatal migration failure.</summary>
    /// <remarks><para><b>Description:</b> source-generated error; the process exits with 1.</para>
    /// <para><b>Business Justification:</b> no traffic without a schema.</para>
    /// <para><b>Side Effects:</b> one log line. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="logger">Logger.</param>
    /// <param name="error">The failure.</param>
    [LoggerMessage(Level = LogLevel.Critical, Message = "database migration failed")]
    private static partial void LogMigrationFailed(ILogger logger, Exception error);
}
