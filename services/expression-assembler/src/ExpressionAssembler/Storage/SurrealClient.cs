// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       expression-assembler
// Module:          AaaS.ExpressionAssembler.Storage.SurrealClient
// Owning Team:     Customer Experience Tribe (CXT)
// Classification:  INTERNAL
// Purpose:         Minimal SurrealDB client over the HTTP RPC endpoint
//                  (POST /rpc, method `query`) with typed variables and
//                  per-statement results.
// Related Docs:    ADR-0014, services/expression-assembler/docs/DEPENDENCIES.md

using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace AaaS.ExpressionAssembler.Storage;

/// <summary>Result of one SurrealQL statement.</summary>
/// <remarks>
/// <para><b>Description:</b> <paramref name="Ok"/> is false when the statement
/// failed; <paramref name="Kind"/> then names the error class reported by
/// SurrealDB (for example <c>AlreadyExists</c>).</para>
/// <para><b>Business Justification:</b> idempotent writes rely on recognising
/// <c>AlreadyExists</c>.</para>
/// <para><b>Thread Safety:</b> immutable record; safe.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <param name="Ok">True when the statement succeeded.</param>
/// <param name="Result">Statement result (JSON), or the error message when it failed.</param>
/// <param name="Kind">Error kind when it failed, otherwise null.</param>
/// <example><code>if (!result.Ok &amp;&amp; result.Kind == "AlreadyExists") { ... }</code></example>
public sealed record StatementResult(bool Ok, JsonNode? Result, string? Kind)
{
    /// <summary>Gets a value indicating whether the statement failed because a record already exists.</summary>
    /// <remarks><para><b>Description:</b> also true for a failed transaction whose
    /// first error was <c>AlreadyExists</c>; see <see cref="SurrealClient.QueryAsync"/>.</para>
    /// <para><b>Business Justification:</b> detects concurrent duplicates.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public bool AlreadyExists => !Ok && Kind == "AlreadyExists";
}

/// <summary>Raised when SurrealDB cannot be reached or rejects a request as a whole.</summary>
/// <remarks>
/// <para><b>Description:</b> transport failures, authentication errors and RPC errors.
/// Statement-level failures are returned as <see cref="StatementResult"/> instead.</para>
/// <para><b>Business Justification:</b> the caller answers 503 for an unavailable database.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>catch (DatabaseUnavailableException) { return Problem(503); }</code></example>
public sealed class DatabaseUnavailableException : Exception
{
    /// <summary>Initializes a new instance of the <see cref="DatabaseUnavailableException"/> class.</summary>
    /// <remarks><para><b>Description:</b> standard exception constructor.</para>
    /// <para><b>Business Justification:</b> see the type documentation.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="message">Description of the failure.</param>
    /// <param name="innerException">The underlying exception, or null.</param>
    public DatabaseUnavailableException(string message, Exception? innerException = null)
        : base(message, innerException)
    {
    }
}

/// <summary>SurrealDB client over HTTP RPC.</summary>
/// <remarks>
/// <para><b>Description:</b> sends <c>{"id":1,"method":"query","params":[sql, vars]}</c>
/// to <c>POST /rpc</c> with a bearer token and the <c>surreal-ns</c> and
/// <c>surreal-db</c> headers. The token comes from one <c>POST /signin</c> with the
/// configured user and password and is reused until one minute before its expiry
/// (the JWT <c>exp</c> claim, one hour for SurrealDB root users); a 401/403 answer or
/// an RPC authentication error renews it once. Basic authentication on every request
/// is avoided on purpose: SurrealDB verifies the password hash (Argon2) per request,
/// which costs 25 to 50 ms of CPU, against about 1 ms with a token (ADR-0014). Variables are passed as typed JSON, never concatenated
/// into the query text; SurrealDB rejects reserved names such as <c>$session</c>,
/// <c>$event</c> or <c>$before</c>, so callers use short neutral names
/// (<c>$sid</c>, <c>$evt</c>, <c>$lim</c>). The <see cref="HttpClient"/> is configured by the host with a
/// 2-second attempt timeout and up to three attempts with jitter (CLAUDE.md 6.1).</para>
/// <para><b>Business Justification:</b> the HTTP RPC endpoint is stable across
/// SurrealDB 2 and 3 and needs no SDK (ADR-0014).</para>
/// <para><b>Thread Safety:</b> safe for concurrent use (the HttpClient is).</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <example><code>var results = await client.QueryAsync("RETURN $x;", new() { ["x"] = 1 }, ct);</code></example>
public sealed class SurrealClient : IDisposable
{
    /// <summary>HTTP client with base address, timeouts and retries configured by the host.</summary>
    /// <remarks><para><b>Description:</b> injected by <c>IHttpClientFactory</c>.</para>
    /// <para><b>Business Justification:</b> resilient database access.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly HttpClient _http;

    /// <summary>Connection settings: credentials, namespace and database.</summary>
    /// <remarks><para><b>Description:</b> from <see cref="AssemblerOptions"/>.</para>
    /// <para><b>Business Justification:</b> configuration, not code.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly AssemblerOptions _options;

    /// <summary>Serialises sign-ins so that concurrent requests share one token.</summary>
    /// <remarks><para><b>Description:</b> held only while signing in.</para>
    /// <para><b>Business Justification:</b> one sign-in per expiry period.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private readonly SemaphoreSlim _signin = new(1, 1);

    /// <summary>Current token and its renewal deadline, or null before the first sign-in.</summary>
    /// <remarks><para><b>Description:</b> an immutable object replaced by reference, so
    /// readers never see a token with another token's deadline.</para>
    /// <para><b>Business Justification:</b> cheap authentication of every query.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    private volatile TokenState? _token;

    /// <summary>Initializes a new instance of the <see cref="SurrealClient"/> class.</summary>
    /// <remarks><para><b>Description:</b> stores its dependencies.</para>
    /// <para><b>Business Justification:</b> see the type documentation.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="http">Client whose base address is the SurrealDB URL.</param>
    /// <param name="options">Service configuration.</param>
    public SurrealClient(HttpClient http, AssemblerOptions options)
    {
        _http = http;
        _options = options;
    }

    /// <summary>Runs SurrealQL statements and returns one result per statement.</summary>
    /// <remarks>
    /// <para><b>Description:</b> with <paramref name="scoped"/> false the namespace and
    /// database headers are omitted, which the migration runner needs to create
    /// them. Inside a failed transaction SurrealDB reports the real error on the
    /// failing statement and a generic error on the others; the
    /// <see cref="StatementResult.AlreadyExists"/> of the failing statement is
    /// therefore the one to inspect.</para>
    /// <para><b>Business Justification:</b> the single gateway to the database.</para>
    /// <para><b>Side Effects:</b> one or more HTTP requests (retries, a sign-in when the
    /// token is missing or rejected); reads and writes as given by <paramref name="sql"/>.</para>
    /// <para><b>Complexity:</b> network bound; O(response size) memory.</para>
    /// <para><b>Thread Safety:</b> safe.</para>
    /// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
    /// </remarks>
    /// <param name="sql">One or more SurrealQL statements.</param>
    /// <param name="variables">Variables referenced as <c>$name</c>; values are serialized to JSON.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <param name="scoped">Whether to send the namespace and database headers.</param>
    /// <returns>One result per statement, in order.</returns>
    /// <exception cref="DatabaseUnavailableException">The request failed, the sign-in or a
    /// renewed token was rejected, or the RPC call returned an error.</exception>
    /// <example><code>var r = await client.QueryAsync("SELECT * FROM task WHERE id = $id;", new() { ["id"] = id }, ct);</code></example>
    public async Task<IReadOnlyList<StatementResult>> QueryAsync(
        string sql,
        Dictionary<string, object?> variables,
        CancellationToken cancellationToken,
        bool scoped = true)
    {
        var body = JsonSerializer.Serialize(new { id = 1, method = "query", @params = new object[] { sql, variables } });
        JsonNode? response = null;
        for (var attempt = 0; attempt < 2; attempt++)
        {
            var token = await GetTokenAsync(renew: attempt > 0, cancellationToken).ConfigureAwait(false);
            using var request = new HttpRequestMessage(HttpMethod.Post, "rpc")
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json"),
            };
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            if (scoped)
            {
                request.Headers.Add("surreal-ns", _options.DatabaseNamespace);
                request.Headers.Add("surreal-db", _options.DatabaseName);
            }

            var (status, text) = await SendAsync(request, cancellationToken).ConfigureAwait(false);
            if (status is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden && attempt == 0)
            {
                continue;
            }

            if ((int)status is < 200 or > 299)
            {
                throw new DatabaseUnavailableException($"SurrealDB answered {(int)status}: {Truncate(text)}");
            }

            try
            {
                response = JsonNode.Parse(text);
            }
            catch (JsonException error)
            {
                throw new DatabaseUnavailableException($"SurrealDB answered invalid JSON: {error.Message}", error);
            }

            if (response?["error"] is { } rpcError)
            {
                var message = rpcError.ToJsonString();
                if (attempt == 0 && (message.Contains("token", StringComparison.OrdinalIgnoreCase)
                    || message.Contains("auth", StringComparison.OrdinalIgnoreCase)))
                {
                    continue;
                }

                throw new DatabaseUnavailableException($"SurrealDB RPC error: {Truncate(message)}");
            }

            break;
        }

        if (response?["result"] is not JsonArray statements)
        {
            throw new DatabaseUnavailableException("SurrealDB RPC response has no result array");
        }

        return statements
            .Select(s => new StatementResult(
                s?["status"]?.GetValue<string>() == "OK",
                s?["result"]?.DeepClone(),
                s?["kind"]?.GetValue<string>()))
            .ToList();
    }

    /// <summary>Releases the sign-in semaphore.</summary>
    /// <remarks><para><b>Description:</b> the HTTP client is owned by the host's
    /// <c>IHttpClientFactory</c> and is not disposed here.</para>
    /// <para><b>Business Justification:</b> deterministic cleanup on shutdown.</para>
    /// <para><b>Side Effects:</b> None beyond releasing the semaphore. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    public void Dispose() => _signin.Dispose();

    /// <summary>Reads the expiry of a JWT from its <c>exp</c> claim.</summary>
    /// <remarks><para><b>Description:</b> decodes the base64url payload without
    /// verifying the signature (the token is only presented back to its issuer).
    /// Returns null when the token has no readable <c>exp</c>.</para>
    /// <para><b>Business Justification:</b> renew the token before it expires.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(token length).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="token">Compact JWT.</param>
    /// <returns>The expiry instant, or null.</returns>
    /// <example><code>SurrealClient.TokenExpiry("h.eyJleHAiOjB9.s") // 1970-01-01T00:00:00Z</code></example>
    internal static DateTimeOffset? TokenExpiry(string token)
    {
        var parts = token.Split('.');
        if (parts.Length < 2)
        {
            return null;
        }

        try
        {
            var payload = parts[1].Replace('-', '+').Replace('_', '/');
            payload = payload.PadRight(payload.Length + ((4 - (payload.Length % 4)) % 4), '=');
            var claims = JsonNode.Parse(Convert.FromBase64String(payload));
            return claims?["exp"] is JsonValue exp && exp.TryGetValue<long>(out var seconds)
                ? DateTimeOffset.FromUnixTimeSeconds(seconds)
                : null;
        }
        catch (Exception error) when (error is FormatException or JsonException)
        {
            return null;
        }
    }

    /// <summary>Shortens a message for logs and exceptions.</summary>
    /// <remarks><para><b>Description:</b> keeps at most 300 characters.</para>
    /// <para><b>Business Justification:</b> bounded error messages.</para>
    /// <para><b>Side Effects:</b> None. <b>Complexity:</b> O(1).</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="text">Any text.</param>
    /// <returns>The text, truncated with an ellipsis when longer than 300 characters.</returns>
    private static string Truncate(string text) => text.Length <= 300 ? text : text[..300] + "…";

    /// <summary>Returns a valid token, signing in when there is none or when asked to renew.</summary>
    /// <remarks><para><b>Description:</b> sends <c>{"user","pass"}</c> to <c>POST /signin</c>;
    /// the token is renewed one minute before its <c>exp</c> claim, or after ten minutes
    /// when the claim is unreadable.</para>
    /// <para><b>Business Justification:</b> see the type documentation.</para>
    /// <para><b>Side Effects:</b> at most one HTTP request.</para>
    /// <para><b>Complexity:</b> O(1).</para>
    /// <para><b>Thread Safety:</b> safe; concurrent callers wait for one sign-in.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="renew">Discard the current token first (after a rejected request).</param>
    /// <param name="cancellationToken">Cancels the sign-in.</param>
    /// <returns>The bearer token.</returns>
    /// <exception cref="DatabaseUnavailableException">The sign-in failed.</exception>
    private async Task<string> GetTokenAsync(bool renew, CancellationToken cancellationToken)
    {
        var current = _token;
        if (!renew && current is not null && current.RenewAt > DateTimeOffset.UtcNow)
        {
            return current.Token;
        }

        await _signin.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            // Another caller may have signed in while this one waited.
            var fresh = _token;
            if (fresh is not null && !ReferenceEquals(fresh, current) && fresh.RenewAt > DateTimeOffset.UtcNow)
            {
                return fresh.Token;
            }

            using var request = new HttpRequestMessage(HttpMethod.Post, "signin")
            {
                Content = new StringContent(
                    JsonSerializer.Serialize(new { user = _options.DatabaseUser, pass = _options.DatabasePassword }),
                    Encoding.UTF8,
                    "application/json"),
            };
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            var (status, text) = await SendAsync(request, cancellationToken).ConfigureAwait(false);
            string? token = null;
            if ((int)status is >= 200 and <= 299)
            {
                try
                {
                    token = JsonNode.Parse(text)?["token"]?.GetValue<string>();
                }
                catch (Exception error) when (error is JsonException or InvalidOperationException)
                {
                    token = null;
                }
            }

            if (string.IsNullOrEmpty(token))
            {
                throw new DatabaseUnavailableException($"SurrealDB sign-in failed with {(int)status}");
            }

            var renewAt = (TokenExpiry(token) ?? DateTimeOffset.UtcNow.AddMinutes(11)).AddMinutes(-1);
            _token = new TokenState(token, renewAt);
            return token;
        }
        finally
        {
            _signin.Release();
        }
    }

    /// <summary>Sends a request and reads the response body.</summary>
    /// <remarks><para><b>Description:</b> transport failures, timeouts and an open
    /// circuit become <see cref="DatabaseUnavailableException"/>.</para>
    /// <para><b>Business Justification:</b> one error type for an unavailable database.</para>
    /// <para><b>Side Effects:</b> one or more HTTP requests (retries of the handler).</para>
    /// <para><b>Complexity:</b> network bound.</para>
    /// <para><b>Owner:</b> CXT. <b>Since:</b> 0.1.0.</para></remarks>
    /// <param name="request">The request.</param>
    /// <param name="cancellationToken">Cancels the request.</param>
    /// <returns>Status code and body.</returns>
    /// <exception cref="DatabaseUnavailableException">The request could not be completed.</exception>
    private async Task<(HttpStatusCode Status, string Text)> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        try
        {
            using var reply = await _http.SendAsync(request, cancellationToken).ConfigureAwait(false);
            return (reply.StatusCode, await reply.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false));
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or TimeoutException
            or Polly.Timeout.TimeoutRejectedException or Polly.CircuitBreaker.BrokenCircuitException)
        {
            throw new DatabaseUnavailableException($"SurrealDB request failed: {error.Message}", error);
        }
    }
}

/// <summary>A SurrealDB bearer token and the instant it must be renewed.</summary>
/// <remarks>
/// <para><b>Description:</b> immutable; held by <see cref="SurrealClient"/>.</para>
/// <para><b>Business Justification:</b> token reuse (ADR-0014).</para>
/// <para><b>Thread Safety:</b> immutable record; safe.</para>
/// <para><b>Owner:</b> Customer Experience Tribe (CXT). <b>Since:</b> expression-assembler 0.1.0.</para>
/// </remarks>
/// <param name="Token">Compact JWT returned by <c>POST /signin</c>.</param>
/// <param name="RenewAt">One minute before the token expires.</param>
internal sealed record TokenState(string Token, DateTimeOffset RenewAt);
