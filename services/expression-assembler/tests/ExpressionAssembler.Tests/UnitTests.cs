// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Tests.UnitTests
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Unit tests of the pure building blocks: expression
//                  assembly, request validation, configuration, timestamps,
//                  log formatting and migration discovery.
// Related Docs:    services/expression-assembler/README.md (Testing)

using AaaS.ExpressionAssembler.Events;
using AaaS.ExpressionAssembler.Keys;
using AaaS.ExpressionAssembler.Observability;
using AaaS.ExpressionAssembler.Storage;
using Microsoft.Extensions.Logging;

namespace AaaS.ExpressionAssembler.Tests;

/// <summary>Tests of <see cref="ExpressionBuilder"/>.</summary>
/// <remarks><para><b>Description:</b> table-driven cases.</para>
/// <para><b>Business Justification:</b> the expression is what the user typed.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para></remarks>
public sealed class ExpressionBuilderTests
{
    /// <summary>Keys after the last C or = form the expression.</summary>
    /// <remarks><para><b>Description:</b> keys are given as a space-separated string.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="keys">Space-separated keys in order.</param>
    /// <param name="expected">Expected expression.</param>
    [Theory]
    [InlineData("2 + 3", "2+3")]
    [InlineData("1 C 2 + 3", "2+3")]
    [InlineData("2 + 3 = 4 + 5", "4+5")]
    [InlineData("2 + + 3", "2++3")]
    [InlineData("C", "")]
    [InlineData("", "")]
    [InlineData("9 9 9 9 9 + 9 9 9 9 9", "99999+99999")]
    public void BuildsTheExpressionSinceTheLastReset(string keys, string expected) =>
        Assert.Equal(expected, ExpressionBuilder.Build(keys.Split(' ', StringSplitOptions.RemoveEmptyEntries)));
}

/// <summary>Tests of <see cref="KeyPressValidator"/>.</summary>
/// <remarks><para><b>Description:</b> valid and invalid requests.</para>
/// <para><b>Business Justification:</b> only calculator keys enter AaaS.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para></remarks>
public sealed class KeyPressValidatorTests
{
    /// <summary>A valid request normalises the session to lowercase.</summary>
    /// <remarks><para><b>Description:</b> uppercase UUIDs are accepted.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    [Fact]
    public void AcceptsAndNormalises()
    {
        var error = KeyPressValidator.Validate(new("5B0F8A54-3C1E-4D6F-9A7B-2E8C1D4F6A90", "C", 9), null, out var press);

        Assert.Null(error);
        Assert.Equal(new KeyPress("5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90", "C", 9), press);
    }

    /// <summary>Invalid fields are rejected with a message.</summary>
    /// <remarks><para><b>Description:</b> one invalid field per case.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="session">sessionId.</param>
    /// <param name="key">key.</param>
    /// <param name="seq">seq.</param>
    /// <param name="idempotencyKey">Header.</param>
    /// <param name="fragment">Expected part of the message.</param>
    [Theory]
    [InlineData(null, "1", 0L, null, "sessionId")]
    [InlineData("not-a-uuid", "1", 0L, null, "sessionId")]
    [InlineData("5b0f8a545c1e4d6f9a7b2e8c1d4f6a90", "1", 0L, null, "sessionId")]
    [InlineData("5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90", "c", 0L, null, "key")]
    [InlineData("5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90", "-", 0L, null, "key")]
    [InlineData("5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90", "1", -1L, null, "seq")]
    [InlineData("5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90", "1", null, null, "seq")]
    [InlineData("5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90", "=", 0L, null, "Idempotency-Key")]
    [InlineData("5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90", "=", 0L, "has space", "Idempotency-Key")]
    public void RejectsInvalidRequests(string? session, string? key, long? seq, string? idempotencyKey, string fragment)
    {
        var error = KeyPressValidator.Validate(new(session, key, seq), idempotencyKey, out var press);

        Assert.Contains(fragment, error, StringComparison.Ordinal);
        Assert.Null(press);
    }

    /// <summary>A missing body is rejected.</summary>
    /// <remarks><para><b>Description:</b> null request.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    [Fact]
    public void RejectsMissingBody() => Assert.NotNull(KeyPressValidator.Validate(null, null, out _));

    /// <summary>An idempotency key of 129 characters is rejected; 128 is accepted.</summary>
    /// <remarks><para><b>Description:</b> length bound.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    [Fact]
    public void BoundsTheIdempotencyKey()
    {
        var request = new KeyPressRequest("5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90", "=", 0);

        Assert.Null(KeyPressValidator.Validate(request, new string('a', 128), out _));
        Assert.NotNull(KeyPressValidator.Validate(request, new string('a', 129), out _));
    }
}

/// <summary>Tests of <see cref="AssemblerOptions"/>.</summary>
/// <remarks><para><b>Description:</b> defaults and validation.</para>
/// <para><b>Business Justification:</b> fail fast on misconfiguration.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para></remarks>
public sealed class AssemblerOptionsTests
{
    /// <summary>Required variables produce options with defaults.</summary>
    /// <remarks><para><b>Description:</b> minimal environment.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    [Fact]
    public void ReadsRequiredVariablesAndDefaults()
    {
        var options = AssemblerOptions.FromEnvironment(Env(new()));

        Assert.Equal("redpanda:9092", options.KafkaBrokers);
        Assert.Equal(new Uri("http://db:8000"), options.DatabaseUrl);
        Assert.Equal(8080, options.HttpPort);
        Assert.Equal("aaas", options.DatabaseNamespace);
        Assert.Equal("expression-assembler", options.ServiceName);
    }

    /// <summary>Invalid or missing values raise.</summary>
    /// <remarks><para><b>Description:</b> one override per case.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="name">Variable.</param>
    /// <param name="value">Value; empty means unset.</param>
    [Theory]
    [InlineData("AAAS_KAFKA_BROKERS", "")]
    [InlineData("AAAS_DB_URL", "")]
    [InlineData("AAAS_DB_URL", "ftp://db")]
    [InlineData("EXPRESSION_ASSEMBLER_DB_PASSWORD", "")]
    [InlineData("AAAS_HTTP_PORT", "70000")]
    [InlineData("AAAS_BOOTSTRAP", "platform")]
    public void RejectsInvalidConfiguration(string name, string value) =>
        Assert.Throws<InvalidOperationException>(() => AssemblerOptions.FromEnvironment(Env(new() { [name] = value })));

    /// <summary>Builds a lookup over a minimal valid environment plus overrides.</summary>
    /// <remarks><para><b>Description:</b> test helper.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="overrides">Variables to set or blank out.</param>
    /// <returns>The lookup function.</returns>
    private static Func<string, string?> Env(Dictionary<string, string> overrides)
    {
        var env = new Dictionary<string, string>
        {
            ["AAAS_KAFKA_BROKERS"] = "redpanda:9092",
            ["AAAS_DB_URL"] = "http://db:8000",
            ["EXPRESSION_ASSEMBLER_DB_PASSWORD"] = "secret",
        };
        foreach (var (key, value) in overrides)
        {
            env[key] = value;
        }

        return name => env.GetValueOrDefault(name);
    }
}

/// <summary>Tests of small helpers: timestamps, log levels, task correlation, migrations.</summary>
/// <remarks><para><b>Description:</b> one fact per helper.</para>
/// <para><b>Business Justification:</b> contract formats and log fields.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para></remarks>
public sealed class HelperTests
{
    /// <summary>Timestamps are UTC with exactly three fractional digits.</summary>
    /// <remarks><para><b>Description:</b> offset input is converted; extra precision truncated.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    [Fact]
    public void FormatsContractTimestamps() =>
        Assert.Equal(
            "2026-10-17T08:00:00.123Z",
            EventFactory.FormatTimestamp(new DateTimeOffset(2026, 10, 17, 10, 0, 0, 123, TimeSpan.FromHours(2)).AddTicks(9999)));

    /// <summary>Generated traceparents are valid W3C values.</summary>
    /// <remarks><para><b>Description:</b> without an activity a random one is made.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    [Fact]
    public void GeneratesTraceparents() =>
        Assert.Matches("^00-[0-9a-f]{32}-[0-9a-f]{16}-01$", EventFactory.CurrentTraceparent());

    /// <summary>Log levels map to the short names.</summary>
    /// <remarks><para><b>Description:</b> warning and critical.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    [Fact]
    public void MapsLogLevels()
    {
        Assert.Equal("warn", JsonLogFormatter.LevelName(LogLevel.Warning));
        Assert.Equal("fatal", JsonLogFormatter.LevelName(LogLevel.Critical));
    }

    /// <summary>The task identifier is found in structured state.</summary>
    /// <remarks><para><b>Description:</b> case-insensitive key.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    [Fact]
    public void FindsTheTaskId()
    {
        Assert.Equal("t1", JsonLogFormatter.FindTaskId(new Dictionary<string, object?> { ["taskId"] = "t1" }));
        Assert.Null(JsonLogFormatter.FindTaskId("plain"));
    }

    /// <summary>The expiry of a SurrealDB token is read from its exp claim.</summary>
    /// <remarks><para><b>Description:</b> base64url payload; malformed tokens give null.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    [Fact]
    public void ReadsTokenExpiry()
    {
        var payload = Convert.ToBase64String("{\"exp\":1792232909}"u8.ToArray()).TrimEnd('=').Replace('+', '-').Replace('/', '_');

        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1792232909), SurrealClient.TokenExpiry($"h.{payload}.s"));
        Assert.Null(SurrealClient.TokenExpiry("not-a-jwt"));
        Assert.Null(SurrealClient.TokenExpiry("h.%%%.s"));
    }

    /// <summary>The migrations of the service are discovered in version order.</summary>
    /// <remarks><para><b>Description:</b> reads <c>MIGRATIONS_DIR</c> or the source tree.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    [Fact]
    public void DiscoversMigrations()
    {
        var migrations = MigrationRunner.Discover(TestPaths.Migrations);

        Assert.Equal(1, migrations[0].Version);
        Assert.EndsWith("0001_initial_schema.surql", migrations[0].Path, StringComparison.Ordinal);
    }
}

/// <summary>Locations of repository files used by the tests.</summary>
/// <remarks><para><b>Description:</b> environment variables set by the Dockerfile, with
/// fallbacks relative to the source tree for local runs.</para>
/// <para><b>Business Justification:</b> tests read the real migrations and contracts.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para></remarks>
internal static class TestPaths
{
    /// <summary>Gets the migrations directory.</summary>
    /// <remarks><para><b>Description:</b> <c>MIGRATIONS_DIR</c> or <c>services/expression-assembler/migrations</c>.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public static string Migrations =>
        Environment.GetEnvironmentVariable("MIGRATIONS_DIR") ?? Path.Combine(ServiceRoot, "migrations");

    /// <summary>Gets the contracts directory.</summary>
    /// <remarks><para><b>Description:</b> <c>CONTRACTS_DIR</c> or the repository <c>contracts</c>.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public static string Contracts =>
        Environment.GetEnvironmentVariable("CONTRACTS_DIR") ?? Path.Combine(ServiceRoot, "..", "..", "contracts");

    /// <summary>Gets the service root, found by walking up to <c>ExpressionAssembler.slnx</c>.</summary>
    /// <remarks><para><b>Description:</b> starts at the test binary directory.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private static string ServiceRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "ExpressionAssembler.slnx")))
            {
                dir = dir.Parent;
            }

            return dir?.FullName ?? throw new InvalidOperationException("service root not found");
        }
    }
}
