// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Tests.EndpointTests
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         HTTP tests of the real application pipeline on an
//                  in-memory test server: status codes, bodies, RFC 9457
//                  problems, health and metrics.
// Related Docs:    services/expression-assembler/docs/API.md, CLAUDE.md 4.1, 6.1

using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using AaaS.ExpressionAssembler.Events;
using AaaS.ExpressionAssembler.Storage;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;

namespace AaaS.ExpressionAssembler.Tests;

/// <summary>HTTP tests of the endpoints.</summary>
/// <remarks>
/// <para><b>Description:</b> the application is built by <see cref="Program.CreateApp"/>
/// with the store and the publisher replaced by fakes and a test server instead of
/// Kestrel.</para>
/// <para><b>Business Justification:</b> the public API contract (CLAUDE.md 4.1) and the
/// operational endpoints (CLAUDE.md 6.1) are verified end to end inside the process.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
public sealed class EndpointTests : IAsyncLifetime
{
    /// <summary>Session used by the tests.</summary>
    /// <remarks><para><b>Description:</b> canonical lowercase UUID.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private const string Session = "5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90";

    /// <summary>Fake store.</summary>
    /// <remarks><para><b>Description:</b> shared with the application.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly InMemoryStore _store = new();

    /// <summary>Fake publisher.</summary>
    /// <remarks><para><b>Description:</b> shared with the application.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly FakePublisher _publisher = new();

    /// <summary>The application under test.</summary>
    /// <remarks><para><b>Description:</b> started in <see cref="InitializeAsync"/>.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private WebApplication? _app;

    /// <summary>Client of the test server.</summary>
    /// <remarks><para><b>Description:</b> created in <see cref="InitializeAsync"/>.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private HttpClient? _client;

    /// <summary>Starts the application on a test server.</summary>
    /// <remarks><para><b>Description:</b> replaces the store and the publisher.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the server runs.</returns>
    public async ValueTask InitializeAsync()
    {
        var options = new AssemblerOptions { KafkaBrokers = "unused:9092", DatabasePassword = "unused" };
        _app = Program.CreateApp(
            options,
            [],
            services =>
            {
                services.AddSingleton<IAssemblerStore>(_store);
                services.AddSingleton<IEventPublisher>(_publisher);
            },
            host => host.UseTestServer());
        await _app.StartAsync(TestContext.Current.CancellationToken);
        _client = _app.GetTestClient();
    }

    /// <summary>Stops the application.</summary>
    /// <remarks><para><b>Description:</b> disposes the client and the application.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when stopped.</returns>
    public async ValueTask DisposeAsync()
    {
        _client?.Dispose();
        if (_app is not null)
        {
            await _app.DisposeAsync();
        }
    }

    /// <summary>A digit answers 204 without a body.</summary>
    /// <remarks><para><b>Description:</b> CLAUDE.md 4.1.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task DigitAnswersNoContent()
    {
        using var response = await Post(new { sessionId = Session, key = "2", seq = 0 });

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
    }

    /// <summary>= answers 202 with the task identifier as JSON.</summary>
    /// <remarks><para><b>Description:</b> body <c>{ "taskId": "…" }</c>.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task EqualsAnswersAcceptedWithTaskId()
    {
        (await Post(new { sessionId = Session, key = "2", seq = 0 })).Dispose();
        using var response = await Post(new { sessionId = Session, key = "=", seq = 1 }, "abc-1");

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestContext.Current.CancellationToken);
        Assert.Equal(_store.Tasks.Single().TaskId, body.GetProperty("taskId").GetString());
    }

    /// <summary>Invalid input answers RFC 9457 problems.</summary>
    /// <remarks><para><b>Description:</b> malformed JSON, missing header, bad key.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="body">Raw request body.</param>
    /// <param name="idempotencyKey">Header value, or null.</param>
    /// <param name="status">Expected status.</param>
    /// <returns>A task completing when the test finishes.</returns>
    [Theory]
    [InlineData("{not json", null, 400)]
    [InlineData("", null, 400)]
    [InlineData("{\"sessionId\":\"5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90\",\"key\":\"=\",\"seq\":0}", null, 400)]
    [InlineData("{\"sessionId\":\"5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90\",\"key\":\"x\",\"seq\":0}", null, 400)]
    [InlineData("{\"sessionId\":\"5b0f8a54-3c1e-4d6f-9a7b-2e8c1d4f6a90\",\"key\":\"=\",\"seq\":0}", "k", 422)]
    public async Task InvalidInputAnswersProblems(string body, string? idempotencyKey, int status)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, Program.KeysPath)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };
        if (idempotencyKey is not null)
        {
            request.Headers.Add("Idempotency-Key", idempotencyKey);
        }

        using var response = await _client!.SendAsync(request, TestContext.Current.CancellationToken);

        Assert.Equal(status, (int)response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var problem = await response.Content.ReadFromJsonAsync<JsonElement>(TestContext.Current.CancellationToken);
        Assert.Equal(status, problem.GetProperty("status").GetInt32());
        Assert.False(string.IsNullOrEmpty(problem.GetProperty("detail").GetString()));
    }

    /// <summary>A broker outage answers a 503 problem.</summary>
    /// <remarks><para><b>Description:</b> the client is told to retry.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task BrokerOutageAnswersServiceUnavailable()
    {
        _publisher.FailNext(1);
        using var response = await Post(new { sessionId = Session, key = "1", seq = 0 });

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
    }

    /// <summary>Health reports every check and turns 503 when one fails.</summary>
    /// <remarks><para><b>Description:</b> healthy, then the broker is unreachable.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task HealthReportsChecks()
    {
        var ok = await _client!.GetFromJsonAsync<JsonElement>("/health", TestContext.Current.CancellationToken);
        Assert.Equal("ok", ok.GetProperty("status").GetString());
        Assert.Equal("ok", ok.GetProperty("checks").GetProperty("database").GetString());

        _publisher.Reachable = false;
        using var response = await _client!.GetAsync(new Uri("/health", UriKind.Relative), TestContext.Current.CancellationToken);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(TestContext.Current.CancellationToken);
        Assert.Equal("error", body.GetProperty("checks").GetProperty("broker").GetString());
    }

    /// <summary>Metrics expose the service counters in the Prometheus text format.</summary>
    /// <remarks><para><b>Description:</b> after one press.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task MetricsExposeCounters()
    {
        (await Post(new { sessionId = Session, key = "3", seq = 0 })).Dispose();
        var text = await _client!.GetStringAsync(new Uri("/metrics", UriKind.Relative), TestContext.Current.CancellationToken);

        Assert.Contains("expression_assembler_key_presses_total", text, StringComparison.Ordinal);
        Assert.Contains("expression_assembler_events_published_total", text, StringComparison.Ordinal);
    }

    /// <summary>Unknown paths answer a 404 problem.</summary>
    /// <remarks><para><b>Description:</b> fallback route.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task UnknownPathAnswersNotFoundProblem()
    {
        using var response = await _client!.GetAsync(new Uri("/nope", UriKind.Relative), TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
    }

    /// <summary>Other methods on the key endpoint answer a 405 problem with Allow: POST.</summary>
    /// <remarks><para><b>Description:</b> GET is the common mistake.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <returns>A task completing when the test finishes.</returns>
    [Fact]
    public async Task OtherMethodsAnswerMethodNotAllowed()
    {
        using var response = await _client!.GetAsync(new Uri(Program.KeysPath, UriKind.Relative), TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.MethodNotAllowed, response.StatusCode);
        Assert.Equal("POST", response.Content.Headers.Allow.Single());
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
    }

    /// <summary>Posts a JSON body to the key endpoint.</summary>
    /// <remarks><para><b>Description:</b> optional idempotency header.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="body">Object serialized as JSON.</param>
    /// <param name="idempotencyKey">Header value, or null.</param>
    /// <returns>The response.</returns>
    private async Task<HttpResponseMessage> Post(object body, string? idempotencyKey = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, Program.KeysPath) { Content = JsonContent.Create(body) };
        if (idempotencyKey is not null)
        {
            request.Headers.Add("Idempotency-Key", idempotencyKey);
        }

        return await _client!.SendAsync(request, TestContext.Current.CancellationToken);
    }
}
