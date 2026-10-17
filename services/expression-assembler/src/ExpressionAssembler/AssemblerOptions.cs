// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.AssemblerOptions
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Configuration of the service, read from environment
//                  variables (bootstrap mode `env`, CLAUDE.md 3) with
//                  validation at startup.
// Related Docs:    services/expression-assembler/README.md (Configuration),
//                  CLAUDE.md 6.1, ADR-0014

namespace AaaS.ExpressionAssembler;

/// <summary>Configuration of expression-assembler, read once at startup.</summary>
/// <remarks>
/// <para><b>Description:</b> Holds every setting the service needs: its name,
/// the HTTP port, the Kafka bootstrap servers, the SurrealDB endpoint and
/// credentials, and the location of the migrations. Values come from
/// environment variables (<see cref="FromEnvironment"/>); there are no
/// hard-coded hosts or passwords (CLAUDE.md 6.1). Until Phase 5 only the
/// bootstrap mode <c>env</c> is supported; <c>platform</c> is rejected.</para>
/// <para><b>Business Justification:</b> A misconfigured assembler would accept
/// key presses it cannot store or forward; failing fast at startup protects the
/// first step of every addition.</para>
/// <para><b>Thread Safety:</b> immutable after construction; safe for concurrent use.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>var options = AssemblerOptions.FromEnvironment(Environment.GetEnvironmentVariable);</code></example>
/// <seealso cref="Program"/>
public sealed record AssemblerOptions
{
    /// <summary>Gets the service name used in logs, events and metrics.</summary>
    /// <remarks><para><b>Description:</b> Variable <c>AAAS_SERVICE</c>, default
    /// <c>expression-assembler</c>; written as <c>producer</c> in every event
    /// envelope, which the contracts require to be exactly this value.</para>
    /// <para><b>Business Justification:</b> one name per service (CLAUDE.md 2).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public string ServiceName { get; init; } = "expression-assembler";

    /// <summary>Gets the environment name (<c>AAAS_ENV</c>, default <c>local</c>).</summary>
    /// <remarks><para><b>Description:</b> Informational; logged at startup.</para>
    /// <para><b>Business Justification:</b> config-server lookups use it from P5.2.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public string Environment { get; init; } = "local";

    /// <summary>Gets the HTTP port inside the container (<c>AAAS_HTTP_PORT</c>, default 8080).</summary>
    /// <remarks><para><b>Description:</b> Serves the API, <c>/health</c> and
    /// <c>/metrics</c>. Allowed range 1..65535.</para>
    /// <para><b>Business Justification:</b> CLAUDE.md 6.1 fixes port 8080.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public int HttpPort { get; init; } = 8080;

    /// <summary>Gets the Kafka bootstrap servers (<c>AAAS_KAFKA_BROKERS</c>).</summary>
    /// <remarks><para><b>Description:</b> Comma-separated <c>host:port</c> list;
    /// <c>redpanda:9092</c> in Compose. Required.</para>
    /// <para><b>Business Justification:</b> every task starts with an event on Redpanda.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public string KafkaBrokers { get; init; } = string.Empty;

    /// <summary>Gets the base URL of SurrealDB (<c>AAAS_DB_URL</c>).</summary>
    /// <remarks><para><b>Description:</b> HTTP endpoint of the service's own
    /// database, <c>http://expression-assembler-db:8000</c> in Compose. Required.</para>
    /// <para><b>Business Justification:</b> key presses and tasks are stored before
    /// any event is published.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public Uri DatabaseUrl { get; init; } = new("http://localhost:8000");

    /// <summary>Gets the SurrealDB user (<c>AAAS_DB_USER</c>, default <c>expression_assembler</c>).</summary>
    /// <remarks><para><b>Description:</b> Root-level user of the dedicated
    /// SurrealDB instance; the same value is given to the database container.</para>
    /// <para><b>Business Justification:</b> authenticated database access only.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public string DatabaseUser { get; init; } = "expression_assembler";

    /// <summary>Gets the SurrealDB password (<c>EXPRESSION_ASSEMBLER_DB_PASSWORD</c>).</summary>
    /// <remarks><para><b>Description:</b> Required; never logged. Moves to
    /// OpenBao in P5.3.</para>
    /// <para><b>Business Justification:</b> credentials are configuration, not code.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public string DatabasePassword { get; init; } = string.Empty;

    /// <summary>Gets the SurrealDB namespace (<c>AAAS_DB_NAMESPACE</c>, default <c>aaas</c>).</summary>
    /// <remarks><para><b>Description:</b> Created by the migration runner if missing.</para>
    /// <para><b>Business Justification:</b> SurrealDB requires a namespace for every query.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public string DatabaseNamespace { get; init; } = "aaas";

    /// <summary>Gets the SurrealDB database (<c>AAAS_DB_NAME</c>, default <c>expression_assembler</c>).</summary>
    /// <remarks><para><b>Description:</b> Created by the migration runner if missing.</para>
    /// <para><b>Business Justification:</b> SurrealDB requires a database for every query.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public string DatabaseName { get; init; } = "expression_assembler";

    /// <summary>Gets the directory of the migration files (<c>AAAS_MIGRATIONS_DIR</c>).</summary>
    /// <remarks><para><b>Description:</b> Default <c>migrations</c> relative to the
    /// application directory (<c>/app/migrations</c> in the image).</para>
    /// <para><b>Business Justification:</b> migrations run at startup (CLAUDE.md 6.1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public string MigrationsDirectory { get; init; } = Path.Combine(AppContext.BaseDirectory, "migrations");

    /// <summary>Reads and validates the configuration.</summary>
    /// <remarks>
    /// <para><b>Description:</b> Applies the defaults documented on each property and
    /// checks that the required values are present and well-formed.</para>
    /// <para><b>Business Justification:</b> fail fast on misconfiguration (CLAUDE.md 6.1).</para>
    /// <para><b>Side Effects:</b> None (the lookup function is the only input).</para>
    /// <para><b>Complexity:</b> O(1) time and memory.</para>
    /// <para><b>Thread Safety:</b> safe; pure function of its argument.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="lookup">Returns the value of an environment variable, or null when unset.</param>
    /// <returns>The validated options.</returns>
    /// <exception cref="InvalidOperationException">A required variable is missing or a value is invalid,
    /// or <c>AAAS_BOOTSTRAP</c> is not <c>env</c>.</exception>
    /// <example><code>
    /// var env = new Dictionary&lt;string, string?&gt; { ["AAAS_KAFKA_BROKERS"] = "redpanda:9092", ... };
    /// var options = AssemblerOptions.FromEnvironment(name =&gt; env.GetValueOrDefault(name));
    /// </code></example>
    public static AssemblerOptions FromEnvironment(Func<string, string?> lookup)
    {
        string Get(string name, string fallback) => string.IsNullOrWhiteSpace(lookup(name)) ? fallback : lookup(name)!.Trim();
        string Require(string name) => string.IsNullOrWhiteSpace(lookup(name))
            ? throw new InvalidOperationException($"environment variable {name} is required")
            : lookup(name)!.Trim();

        var bootstrap = Get("AAAS_BOOTSTRAP", "env");
        if (bootstrap != "env")
        {
            throw new InvalidOperationException($"AAAS_BOOTSTRAP={bootstrap} is not supported before P5.2; use env");
        }

        var portText = Get("AAAS_HTTP_PORT", "8080");
        if (!int.TryParse(portText, out var port) || port is < 1 or > 65535)
        {
            throw new InvalidOperationException($"AAAS_HTTP_PORT={portText} is not a port number");
        }

        var urlText = Require("AAAS_DB_URL");
        if (!Uri.TryCreate(urlText, UriKind.Absolute, out var url) || (url.Scheme != "http" && url.Scheme != "https"))
        {
            throw new InvalidOperationException($"AAAS_DB_URL={urlText} is not an http(s) URL");
        }

        return new AssemblerOptions
        {
            ServiceName = Get("AAAS_SERVICE", "expression-assembler"),
            Environment = Get("AAAS_ENV", "local"),
            HttpPort = port,
            KafkaBrokers = Require("AAAS_KAFKA_BROKERS"),
            DatabaseUrl = url,
            DatabaseUser = Get("AAAS_DB_USER", "expression_assembler"),
            DatabasePassword = Require("EXPRESSION_ASSEMBLER_DB_PASSWORD"),
            DatabaseNamespace = Get("AAAS_DB_NAMESPACE", "aaas"),
            DatabaseName = Get("AAAS_DB_NAME", "expression_assembler"),
            MigrationsDirectory = Get("AAAS_MIGRATIONS_DIR", Path.Combine(AppContext.BaseDirectory, "migrations")),
        };
    }
}
