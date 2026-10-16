using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Fasty.Api.Modules.Identity;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Xunit;

namespace Fasty.Api.Tests;

public sealed class PasswordRecoveryRedemptionIntegrationTests
    : IClassFixture<FastyApiFactory>
{
    private const string AdminHeader =
        "X-Fasty-Recovery-Admin-Secret";

    private const string AdminSecret =
        "fasty-test-recovery-admin-secret-2026-value";

    private readonly FastyApiFactory _factory;

    public PasswordRecoveryRedemptionIntegrationTests(
        FastyApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Recovery_redemption_endpoint_is_hidden_when_disabled()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/password-recovery/redeem",
                new
                {
                    email =
                        "disabled-recovery@example.com",
                    recoveryCredential =
                        "unused-credential",
                    newPassword =
                        "Replacement456!"
                });

        Assert.Equal(
            HttpStatusCode.NotFound,
            response.StatusCode);
    }

    [Fact]
    public async Task Recovery_redemption_changes_password_consumes_credential_and_revokes_sessions()
    {
        await _factory.ResetStorageAsync();

        const string email =
            "recovery-redeem-success@example.com";

        const string oldPassword =
            "StrongPassword123!";

        const string newPassword =
            "Replacement456!";

        using var factory =
            CreateEnabledFactory();

        await CreateUserWithPasswordAsync(
            factory,
            email,
            oldPassword);

        using var client =
            factory.CreateClient();

        using var loginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password =
                        oldPassword,
                    deviceName =
                        "Recovery pre-reset session"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            loginResponse.StatusCode);

        var loginBody =
            await loginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var refreshToken =
            loginBody
                .GetProperty("refreshToken")
                .GetString();

        Assert.False(
            string.IsNullOrWhiteSpace(
                refreshToken));

        var recoveryCredential =
            await IssueCredentialAsync(
                client,
                email);

        using var redeemResponse =
            await client.PostAsJsonAsync(
                "/api/auth/password-recovery/redeem",
                new
                {
                    email,
                    recoveryCredential,
                    newPassword
                });

        Assert.Equal(
            HttpStatusCode.OK,
            redeemResponse.StatusCode);

        using var replayResponse =
            await client.PostAsJsonAsync(
                "/api/auth/password-recovery/redeem",
                new
                {
                    email,
                    recoveryCredential,
                    newPassword =
                        "AnotherReplacement789!"
                });

        Assert.Equal(
            HttpStatusCode.BadRequest,
            replayResponse.StatusCode);

        var replayBody =
            await replayResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.Equal(
            "The recovery credential is invalid or expired.",
            replayBody
                .GetProperty("message")
                .GetString());

        using var refreshResponse =
            await client.PostAsJsonAsync(
                "/api/auth/refresh",
                new
                {
                    refreshToken
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            refreshResponse.StatusCode);

        using var oldLoginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password =
                        oldPassword,
                    deviceName =
                        "Old recovery password"
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            oldLoginResponse.StatusCode);

        using var newLoginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password =
                        newPassword,
                    deviceName =
                        "New recovery password"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            newLoginResponse.StatusCode);

        var consumedCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.password_recovery_credentials
                WHERE "UserId" =
                (
                    SELECT "Id"
                    FROM auth.users
                    WHERE "NormalizedEmail" = @email
                )
                AND "ConsumedAt" IS NOT NULL;
                """,
                new NpgsqlParameter(
                    "email",
                    email.ToUpperInvariant()));

        Assert.Equal(
            1,
            consumedCount);
    }

    [Fact]
    public async Task Invalid_unknown_and_expired_recovery_credentials_share_generic_failure()
    {
        await _factory.ResetStorageAsync();

        const string email =
            "recovery-invalid@example.com";

        using var factory =
            CreateEnabledFactory();

        await CreateUserWithPasswordAsync(
            factory,
            email,
            "StrongPassword123!");

        using var client =
            factory.CreateClient();

        using var invalidResponse =
            await client.PostAsJsonAsync(
                "/api/auth/password-recovery/redeem",
                new
                {
                    email,
                    recoveryCredential =
                        "definitely-invalid",
                    newPassword =
                        "Replacement456!"
                });

        using var unknownResponse =
            await client.PostAsJsonAsync(
                "/api/auth/password-recovery/redeem",
                new
                {
                    email =
                        "unknown-recovery@example.com",
                    recoveryCredential =
                        "definitely-invalid",
                    newPassword =
                        "Replacement456!"
                });

        var recoveryCredential =
            await IssueCredentialAsync(
                client,
                email);

        var recoveryHash =
            Convert.ToHexString(
                System.Security.Cryptography.SHA256.HashData(
                    System.Text.Encoding.UTF8.GetBytes(
                        recoveryCredential)));

        await _factory.ExecuteSqlAsync(
            """
            UPDATE auth.password_recovery_credentials
            SET "ExpiresAt" =
                CURRENT_TIMESTAMP - INTERVAL '1 minute'
            WHERE "TokenHash" = @tokenHash;
            """,
            new NpgsqlParameter(
                "tokenHash",
                recoveryHash));

        using var expiredResponse =
            await client.PostAsJsonAsync(
                "/api/auth/password-recovery/redeem",
                new
                {
                    email,
                    recoveryCredential,
                    newPassword =
                        "Replacement456!"
                });

        Assert.Equal(
            HttpStatusCode.BadRequest,
            invalidResponse.StatusCode);

        Assert.Equal(
            HttpStatusCode.BadRequest,
            unknownResponse.StatusCode);

        Assert.Equal(
            HttpStatusCode.BadRequest,
            expiredResponse.StatusCode);

        var invalidMessage =
            await ReadMessageAsync(
                invalidResponse);

        var unknownMessage =
            await ReadMessageAsync(
                unknownResponse);

        var expiredMessage =
            await ReadMessageAsync(
                expiredResponse);

        Assert.Equal(
            invalidMessage,
            unknownMessage);

        Assert.Equal(
            invalidMessage,
            expiredMessage);

        Assert.Equal(
            "The recovery credential is invalid or expired.",
            invalidMessage);
    }

    [Fact]
    public async Task Weak_password_does_not_consume_recovery_credential()
    {
        await _factory.ResetStorageAsync();

        const string email =
            "recovery-weak-password@example.com";

        using var factory =
            CreateEnabledFactory();

        await CreateUserWithPasswordAsync(
            factory,
            email,
            "StrongPassword123!");

        using var client =
            factory.CreateClient();

        var recoveryCredential =
            await IssueCredentialAsync(
                client,
                email);

        using var weakResponse =
            await client.PostAsJsonAsync(
                "/api/auth/password-recovery/redeem",
                new
                {
                    email,
                    recoveryCredential,
                    newPassword =
                        "weak"
                });

        Assert.Equal(
            HttpStatusCode.BadRequest,
            weakResponse.StatusCode);

        var weakBody =
            await weakResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.True(
            weakBody.TryGetProperty(
                "errors",
                out _));

        using var validResponse =
            await client.PostAsJsonAsync(
                "/api/auth/password-recovery/redeem",
                new
                {
                    email,
                    recoveryCredential,
                    newPassword =
                        "Replacement456!"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            validResponse.StatusCode);
    }

    [Fact]
    public async Task Concurrent_recovery_redemption_allows_only_one_success()
    {
        await _factory.ResetStorageAsync();

        const string email =
            "recovery-concurrent@example.com";

        using var factory =
            CreateEnabledFactory();

        await CreateUserWithPasswordAsync(
            factory,
            email,
            "StrongPassword123!");

        using var client =
            factory.CreateClient();

        var recoveryCredential =
            await IssueCredentialAsync(
                client,
                email);

        var firstTask =
            client.PostAsJsonAsync(
                "/api/auth/password-recovery/redeem",
                new
                {
                    email,
                    recoveryCredential,
                    newPassword =
                        "Replacement456!"
                });

        var secondTask =
            client.PostAsJsonAsync(
                "/api/auth/password-recovery/redeem",
                new
                {
                    email,
                    recoveryCredential,
                    newPassword =
                        "Replacement456!"
                });

        await Task.WhenAll(
            firstTask,
            secondTask);

        using var firstResponse =
            await firstTask;

        using var secondResponse =
            await secondTask;

        var statuses =
            new[]
            {
                firstResponse.StatusCode,
                secondResponse.StatusCode
            };

        Assert.Equal(
            1,
            statuses.Count(
                status =>
                    status == HttpStatusCode.OK));

        Assert.Equal(
            1,
            statuses.Count(
                status =>
                    status == HttpStatusCode.BadRequest));
    }

    private WebApplicationFactory<Program>
        CreateEnabledFactory()
    {
        return _factory.WithWebHostBuilder(
            builder =>
            {
                builder.ConfigureAppConfiguration(
                    (_, configuration) =>
                    {
                        configuration.AddInMemoryCollection(
                            new Dictionary<string, string?>
                            {
                                ["Authentication:RecoveryAdmin:Enabled"] =
                                    "true",
                                ["Authentication:RecoveryAdmin:Secret"] =
                                    AdminSecret,
                                ["Authentication:RecoveryAdmin:CredentialLifetimeMinutes"] =
                                    "30"
                            });
                    });
            });
    }

    private static async Task CreateUserWithPasswordAsync(
        WebApplicationFactory<Program> factory,
        string email,
        string password)
    {
        await using var scope =
            factory.Services.CreateAsyncScope();

        var userManager =
            scope.ServiceProvider
                .GetRequiredService<
                    UserManager<ApplicationUser>>();

        var user =
            new ApplicationUser
            {
                Id =
                    Guid.NewGuid(),
                UserName =
                    email,
                Email =
                    email,
                EmailConfirmed =
                    true,
                CreatedAt =
                    DateTimeOffset.UtcNow
            };

        var result =
            await userManager.CreateAsync(
                user,
                password);

        Assert.True(
            result.Succeeded,
            string.Join(
                "; ",
                result.Errors.Select(
                    error =>
                        $"{error.Code}: {error.Description}")));
    }

    private static async Task<string> IssueCredentialAsync(
        HttpClient client,
        string email)
    {
        using var request =
            new HttpRequestMessage(
                HttpMethod.Post,
                "/api/auth/admin/password-recovery-credentials")
            {
                Content =
                    JsonContent.Create(
                        new
                        {
                            email
                        })
            };

        request.Headers.Add(
            AdminHeader,
            AdminSecret);

        using var response =
            await client.SendAsync(
                request);

        response.EnsureSuccessStatusCode();

        var body =
            await response.Content
                .ReadFromJsonAsync<JsonElement>();

        var recoveryCredential =
            body
                .GetProperty("recoveryCredential")
                .GetString();

        Assert.False(
            string.IsNullOrWhiteSpace(
                recoveryCredential));

        return recoveryCredential!;
    }

    private static async Task<string?> ReadMessageAsync(
        HttpResponseMessage response)
    {
        var body =
            await response.Content
                .ReadFromJsonAsync<JsonElement>();

        return body
            .GetProperty("message")
            .GetString();
    }
}
