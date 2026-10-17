// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Tests.SurrealStoreTests
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Tests of the SurrealDB store and the migration runner
//                  against a real SurrealDB process (in-memory storage)
//                  started from the binary named by SURREAL_BIN.
// Related Docs:    migrations/0001_initial_schema.surql, ADR-0014

using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using AaaS.ExpressionAssembler.Storage;
using Microsoft.Extensions.Logging.Abstractions;

namespace AaaS.ExpressionAssembler.Tests;

/// <summary>Starts one SurrealDB process for the storage tests.</summary>
/// <remarks>
/// <para><b>Description:</b> runs <c>surreal start memory</c> on a free loopback port with
/// a test user, waits until it answers, applies the migrations, and stops the
/// process at the end. When <c>SURREAL_BIN</c> is unset (a host without the binary)
/// <see cref="Available"/> is false and the tests are skipped; the Docker test stage
/// always sets it.</para>
/// <para><b>Business Justification:</b> the SurrealQL of the store is verified against the
/// database engine that runs it in production.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
public sealed class SurrealFixture : IAsyncLifetime
{
    /// <summary>The database process, or null when unavailable.</summary>
    /// <remarks><para><b>Description:</b> killed on disposal.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private Process? _process;

    /// <summary>Gets a value indicating whether a SurrealDB binary is configured.</summary>
    /// <remarks><para><b>Description:</b> <c>SURREAL_BIN</c> is set.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public static bool Available => Environment.GetEnvironmentVariable("SURREAL_BIN") is { Length: > 0 };

    /// <summary>Gets the client connected to the test database.</summary>
    /// <remarks><para><b>Description:</b> created in <see cref="InitializeAsync"/>.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public SurrealClient? Client { get; private set; }

    /// <summary>Gets the number of migrations applied by the first run.</summary>
    /// <remarks><para><b>Description:</b> asserted by the tests.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public int AppliedOnFirstRun { get; private set; }

    /// <summary>Gets the runner, for re-running the migrations.</summary>
    /// <remarks><para><b>Description:</b> created in <see cref="InitializeAsync"/>.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public MigrationRunner? Runner { get; private set; }

    /// <summary>Starts SurrealDB and applies the migrations.</summary>
    /// <remarks><para><b>Description:</b> polls <c>/health</c> for up to 20 seconds.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the database is ready.</returns>
    public async ValueTask InitializeAsync()
    {
        if (!Available)
        {
            return;
        }

        var port = FreePort();
        _process = Process.Start(new ProcessStartInfo(
            Environment.GetEnvironmentVariable("SURREAL_BIN")!,
            $"start --log warn --user tester --pass test-secret --bind 127.0.0.1:{port} memory")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        })!;
        var url = new Uri($"http://127.0.0.1:{port}/");
        using var probe = new HttpClient { BaseAddress = url };
        for (var i = 0; ; i++)
        {
            try
            {
                using var health = await probe.GetAsync(new Uri("health", UriKind.Relative));
                if (health.IsSuccessStatusCode)
                {
                    break;
                }
            }
            catch (HttpRequestException) when (i < 200)
            {
            }

            await Task.Delay(100);
        }

        var options = new AssemblerOptions
        {
            DatabaseUrl = url,
            DatabaseUser = "tester",
            DatabasePassword = "test-secret",
            MigrationsDirectory = TestPaths.Migrations,
        };
        Client = new SurrealClient(new HttpClient { BaseAddress = url, Timeout = TimeSpan.FromSeconds(5) }, options);
        Runner = new MigrationRunner(Client, options, NullLogger<MigrationRunner>.Instance);
        AppliedOnFirstRun = await Runner.RunAsync(CancellationToken.None);
    }

    /// <summary>Stops SurrealDB.</summary>
    /// <remarks><para><b>Description:</b> kills the process tree.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A completed task.</returns>
    public ValueTask DisposeAsync()
    {
        if (_process is { HasExited: false })
        {
            _process.Kill(entireProcessTree: true);
        }

        _process?.Dispose();
        return ValueTask.CompletedTask;
    }

    /// <summary>Finds a free TCP port on the loopback interface.</summary>
    /// <remarks><para><b>Description:</b> binds port 0 and releases it.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>The port number.</returns>
    private static int FreePort()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        return ((IPEndPoint)listener.LocalEndpoint).Port;
    }
}

/// <summary>Tests of <see cref="SurrealAssemblerStore"/> and <see cref="MigrationRunner"/>.</summary>
/// <remarks>
/// <para><b>Description:</b> each test uses its own session and keys, so the shared
/// database needs no cleanup.</para>
/// <para><b>Business Justification:</b> idempotent writes and transactions must hold in
/// the real engine, not only in the fake.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <param name="db">Shared database fixture.</param>
public sealed class SurrealStoreTests(SurrealFixture db) : IClassFixture<SurrealFixture>
{
    /// <summary>Migrations are applied once and are not re-applied.</summary>
    /// <remarks><para><b>Description:</b> the second run applies nothing.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task MigrationsRunOnce()
    {
        RequireDatabase();

        Assert.Equal(MigrationRunner.Discover(TestPaths.Migrations).Count, db.AppliedOnFirstRun);
        Assert.Equal(0, await db.Runner!.RunAsync(TestContext.Current.CancellationToken));
    }

    /// <summary>Key presses are created once, read back, ordered and marked published.</summary>
    /// <remarks><para><b>Description:</b> duplicates report false.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task KeyPressesAreIdempotentAndOrdered()
    {
        var store = Store();
        var session = Guid.NewGuid().ToString("D");
        var ct = TestContext.Current.CancellationToken;

        Assert.True(await store.TryCreateKeyPressAsync(Press(session, 1, "+"), ct));
        Assert.True(await store.TryCreateKeyPressAsync(Press(session, 0, "2"), ct));
        Assert.True(await store.TryCreateKeyPressAsync(Press(session, 2, "3"), ct));
        Assert.False(await store.TryCreateKeyPressAsync(Press(session, 0, "9"), ct));

        Assert.Equal(["2", "+"], await store.GetKeysBeforeAsync(session, 2, ct));
        var stored = await store.GetKeyPressAsync(session, 0, ct);
        Assert.Equal("2", stored!.Key);
        Assert.Equal("2026-10-17T10:00:00.000Z", stored.ReceivedAt);
        Assert.False(stored.Published);

        await store.MarkKeyPressPublishedAsync(session, 0, ct);
        Assert.True((await store.GetKeyPressAsync(session, 0, ct))!.Published);
        Assert.Null(await store.GetKeyPressAsync(session, 99, ct));
    }

    /// <summary>A task is created atomically with its key and the link from its press.</summary>
    /// <remarks><para><b>Description:</b> a second task with the same key is refused and
    /// leaves no trace.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task TasksAreUniquePerIdempotencyKey()
    {
        var store = Store();
        var session = Guid.NewGuid().ToString("D");
        var key = $"key-{Guid.NewGuid():N}";
        var ct = TestContext.Current.CancellationToken;
        await store.TryCreateKeyPressAsync(Press(session, 1, "="), ct);
        await store.TryCreateKeyPressAsync(Press(session, 2, "="), ct);

        var first = NewTask(session, 1, key);
        Assert.True(await store.TryCreateTaskAsync(first, ct));
        Assert.False(await store.TryCreateTaskAsync(NewTask(session, 2, key), ct));

        Assert.Equal(first, await store.GetTaskByIdempotencyKeyAsync(key, ct));
        Assert.Equal(first.TaskId, (await store.GetKeyPressAsync(session, 1, ct))!.TaskId);
        Assert.Null((await store.GetKeyPressAsync(session, 2, ct))!.TaskId);

        await store.MarkTaskPublishedAsync(first.TaskId, ct);
        Assert.True((await store.GetTaskByIdempotencyKeyAsync(key, ct))!.Published);
        Assert.Null(await store.GetTaskByIdempotencyKeyAsync("unknown", ct));
    }

    /// <summary>The schema rejects keys outside the calculator.</summary>
    /// <remarks><para><b>Description:</b> the ASSERT of <c>key_press.key</c>.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task SchemaRejectsUnknownKeys()
    {
        var store = Store();

        await Assert.ThrowsAsync<DatabaseUnavailableException>(() =>
            store.TryCreateKeyPressAsync(Press(Guid.NewGuid().ToString("D"), 0, "x"), TestContext.Current.CancellationToken));
    }

    /// <summary>Ping succeeds against the running database.</summary>
    /// <remarks><para><b>Description:</b> health check query.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task PingSucceeds() => Assert.True(await Store().PingAsync(TestContext.Current.CancellationToken));

    /// <summary>Builds a key press record.</summary>
    /// <remarks><para><b>Description:</b> fixed timestamp and trace.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="session">Session.</param>
    /// <param name="seq">Position.</param>
    /// <param name="key">Key.</param>
    /// <returns>The record.</returns>
    private static KeyPressRecord Press(string session, long seq, string key) =>
        new(session, seq, key, "2026-10-17T10:00:00.000Z", "{}", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", false, null);

    /// <summary>Builds a task record.</summary>
    /// <remarks><para><b>Description:</b> fresh UUIDv7.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="session">Session.</param>
    /// <param name="seq">Position of the = press.</param>
    /// <param name="key">Idempotency key.</param>
    /// <returns>The record.</returns>
    private static TaskRecord NewTask(string session, long seq, string key) =>
        new(Guid.CreateVersion7().ToString("D"), session, seq, "42", key, "2026-10-17T10:00:01.500Z", "{}", "tp", false);

    /// <summary>Skips the test when no SurrealDB binary is configured.</summary>
    /// <remarks><para><b>Description:</b> xUnit v3 dynamic skip.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private static void RequireDatabase() => Assert.SkipUnless(SurrealFixture.Available, "SURREAL_BIN is not set");

    /// <summary>Returns a store over the fixture database.</summary>
    /// <remarks><para><b>Description:</b> skips when unavailable.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>The store.</returns>
    private SurrealAssemblerStore Store()
    {
        RequireDatabase();
        return new SurrealAssemblerStore(db.Client!);
    }
}
