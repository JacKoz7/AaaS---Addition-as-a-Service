// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Storage.MigrationRunner
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Applies the versioned SurrealQL migrations in migrations/
//                  at startup, each in one transaction with its row in the
//                  `migration` table.
// Related Docs:    CLAUDE.md 6.1 (migrations at startup), ADR-0014,
//                  services/expression-assembler/migrations/

using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace AaaS.ExpressionAssembler.Storage;

/// <summary>Applies pending database migrations.</summary>
/// <remarks>
/// <para><b>Description:</b> migration files are named <c>NNNN_description.surql</c>;
/// the number is the version. On startup the runner creates the namespace, the
/// database and the <c>migration</c> table if missing, then applies every file whose
/// version is not recorded, in ascending order. A file and its <c>migration</c> row are
/// committed in one transaction, so a failed migration leaves no trace and is retried
/// on the next start. Applied files are never re-run, so they must never be edited.</para>
/// <para><b>Business Justification:</b> CLAUDE.md 6.1 requires versioned migrations run
/// at startup; the schema of the key press store must exist before the first click.</para>
/// <para><b>Thread Safety:</b> run once per process, before the server starts.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>await new MigrationRunner(client, options, logger).RunAsync(ct);</code></example>
public sealed partial class MigrationRunner
{
    /// <summary>Definition of the bookkeeping table, created before any migration.</summary>
    /// <remarks><para><b>Description:</b> idempotent (<c>IF NOT EXISTS</c>); one record
    /// per applied version, <c>migration:⟨version⟩</c>.</para>
    /// <para><b>Business Justification:</b> records which migrations ran.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private const string MigrationTable =
        "DEFINE TABLE IF NOT EXISTS migration SCHEMAFULL COMMENT \"Applied schema migrations, one record per version.\";"
        + "DEFINE FIELD IF NOT EXISTS version ON migration TYPE int COMMENT \"Version number from the migration file name.\";"
        + "DEFINE FIELD IF NOT EXISTS name ON migration TYPE string COMMENT \"File name of the migration.\";"
        + "DEFINE FIELD IF NOT EXISTS applied_at ON migration TYPE datetime COMMENT \"Instant the migration was committed.\";";

    /// <summary>The SurrealDB client.</summary>
    /// <remarks><para><b>Description:</b> used unscoped for the namespace and database.</para>
    /// <para><b>Business Justification:</b> database access.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly SurrealClient _client;

    /// <summary>Service configuration: namespace, database and migrations directory.</summary>
    /// <remarks><para><b>Description:</b> from <see cref="AssemblerOptions"/>.</para>
    /// <para><b>Business Justification:</b> configuration, not code.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly AssemblerOptions _options;

    /// <summary>Logger for applied migrations.</summary>
    /// <remarks><para><b>Description:</b> one line per applied file.</para>
    /// <para><b>Business Justification:</b> auditable schema changes.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly ILogger<MigrationRunner> _logger;

    /// <summary>Initializes a new instance of the <see cref="MigrationRunner"/> class.</summary>
    /// <remarks><para><b>Description:</b> stores its dependencies.</para>
    /// <para><b>Business Justification:</b> see the type documentation.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="client">SurrealDB client.</param>
    /// <param name="options">Service configuration.</param>
    /// <param name="logger">Logger.</param>
    public MigrationRunner(SurrealClient client, AssemblerOptions options, ILogger<MigrationRunner> logger)
    {
        _client = client;
        _options = options;
        _logger = logger;
    }

    /// <summary>Lists the migration files of a directory in version order.</summary>
    /// <remarks>
    /// <para><b>Description:</b> files not matching <c>NNNN_name.surql</c> are ignored;
    /// two files with the same version are an error.</para>
    /// <para><b>Business Justification:</b> deterministic migration order.</para>
    /// <para><b>Side Effects:</b> lists one directory.</para>
    /// <para><b>Complexity:</b> O(n log n) in the number of files.</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="directory">Directory to scan.</param>
    /// <returns>Version and path of each migration, ascending.</returns>
    /// <exception cref="InvalidOperationException">The directory is missing or two files share a version.</exception>
    /// <example><code>MigrationRunner.Discover("/app/migrations") // [(1, ".../0001_initial_schema.surql")]</code></example>
    public static IReadOnlyList<(int Version, string Path)> Discover(string directory)
    {
        if (!Directory.Exists(directory))
        {
            throw new InvalidOperationException($"migrations directory {directory} does not exist");
        }

        var migrations = Directory.EnumerateFiles(directory, "*.surql")
            .Select(path => (Match: FileNamePattern().Match(System.IO.Path.GetFileName(path)), Path: path))
            .Where(m => m.Match.Success)
            .Select(m => (Version: int.Parse(m.Match.Groups[1].Value, CultureInfo.InvariantCulture), m.Path))
            .OrderBy(m => m.Version)
            .ToList();
        var duplicate = migrations.GroupBy(m => m.Version).FirstOrDefault(g => g.Count() > 1);
        if (duplicate is not null)
        {
            throw new InvalidOperationException($"two migrations have version {duplicate.Key}");
        }

        return migrations;
    }

    /// <summary>Applies every pending migration.</summary>
    /// <remarks>
    /// <para><b>Description:</b> see the type documentation. The namespace and database
    /// names are validated as identifiers before they are written into the
    /// <c>DEFINE</c> statements, which cannot take variables.</para>
    /// <para><b>Business Justification:</b> schema before traffic.</para>
    /// <para><b>Side Effects:</b> creates the namespace, database and tables; writes
    /// <c>migration</c> records; logs each applied file.</para>
    /// <para><b>Complexity:</b> O(total size of the pending migrations).</para>
    /// <para><b>Thread Safety:</b> not safe; run once per process.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="cancellationToken">Cancels the run.</param>
    /// <returns>The number of migrations applied.</returns>
    /// <exception cref="InvalidOperationException">An identifier is invalid, a file is malformed,
    /// or a migration failed.</exception>
    /// <exception cref="DatabaseUnavailableException">The database could not be reached.</exception>
    /// <example><code>var applied = await runner.RunAsync(ct);</code></example>
    public async Task<int> RunAsync(CancellationToken cancellationToken)
    {
        foreach (var name in new[] { _options.DatabaseNamespace, _options.DatabaseName })
        {
            if (!IdentifierPattern().IsMatch(name))
            {
                throw new InvalidOperationException($"'{name}' is not a valid SurrealDB identifier");
            }
        }

        Require(
            await _client.QueryAsync(
                $"DEFINE NAMESPACE IF NOT EXISTS {_options.DatabaseNamespace}; USE NS {_options.DatabaseNamespace}; "
                + $"DEFINE DATABASE IF NOT EXISTS {_options.DatabaseName};",
                [],
                cancellationToken,
                scoped: false).ConfigureAwait(false),
            "creating the namespace and database");
        Require(await _client.QueryAsync(MigrationTable, [], cancellationToken).ConfigureAwait(false), "creating the migration table");

        var appliedRows = Require(
            await _client.QueryAsync("SELECT VALUE version FROM migration;", [], cancellationToken).ConfigureAwait(false),
            "reading applied migrations")[0].Result as JsonArray;
        var applied = appliedRows?.Select(v => v!.GetValue<int>()).ToHashSet() ?? [];

        var count = 0;
        foreach (var (version, path) in Discover(_options.MigrationsDirectory))
        {
            if (applied.Contains(version))
            {
                continue;
            }

            var name = System.IO.Path.GetFileName(path);
            var script = await File.ReadAllTextAsync(path, cancellationToken).ConfigureAwait(false);
            Require(
                await _client.QueryAsync(
                    "BEGIN TRANSACTION;\n" + script + "\nCREATE type::record('migration', $version) CONTENT "
                    + "{ version: $version, name: $name, applied_at: time::now() } RETURN NONE;\nCOMMIT TRANSACTION;",
                    new() { ["version"] = version, ["name"] = name },
                    cancellationToken).ConfigureAwait(false),
                $"applying {name}");
            LogApplied(_logger, version, name);
            count++;
        }

        return count;
    }

    /// <summary>Raises when any statement failed.</summary>
    /// <remarks><para><b>Description:</b> includes the first error message.</para>
    /// <para><b>Business Justification:</b> a failed migration stops the service.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(n).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="results">Statement results.</param>
    /// <param name="what">Description of the operation for the message.</param>
    /// <returns>The results, when all succeeded.</returns>
    /// <exception cref="InvalidOperationException">A statement failed.</exception>
    private static IReadOnlyList<StatementResult> Require(IReadOnlyList<StatementResult> results, string what)
    {
        var failed = results.FirstOrDefault(r => !r.Ok);
        return failed is null ? results : throw new InvalidOperationException($"{what} failed: {failed.Result}");
    }

    /// <summary>Logs an applied migration.</summary>
    /// <remarks><para><b>Description:</b> source-generated logging method.</para>
    /// <para><b>Business Justification:</b> auditable schema changes.</para>
    /// <para><b>Side Effects:</b> one log line. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="logger">Logger.</param>
    /// <param name="version">Applied version.</param>
    /// <param name="name">File name.</param>
    [LoggerMessage(Level = LogLevel.Information, Message = "applied migration {Version} ({Name})")]
    private static partial void LogApplied(ILogger logger, int version, string name);

    /// <summary>Pattern of a migration file name; group 1 is the version.</summary>
    /// <remarks><para><b>Description:</b> four or more digits, underscore, name, <c>.surql</c>.</para>
    /// <para><b>Business Justification:</b> versioned migrations.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>The compiled expression.</returns>
    [GeneratedRegex(@"^(\d{4,})_[a-z0-9_]+\.surql$")]
    private static partial Regex FileNamePattern();

    /// <summary>Pattern of a SurrealDB namespace or database identifier.</summary>
    /// <remarks><para><b>Description:</b> lowercase letters, digits and underscores.</para>
    /// <para><b>Business Justification:</b> identifiers are interpolated into DDL; the
    /// pattern rules out injection.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>The compiled expression.</returns>
    [GeneratedRegex("^[a-z_][a-z0-9_]{0,63}$")]
    private static partial Regex IdentifierPattern();
}
