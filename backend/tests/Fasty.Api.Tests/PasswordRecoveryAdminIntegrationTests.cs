using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace Fasty.Api.Tests;

public sealed class PasswordRecoveryAdminIntegrationTests
    : IClassFixture<FastyApiFactory>
{
    private const string AdminHeader =
        "X-Fasty-Recovery-Admin-Secret";

    private const string AdminSecret =
        "fasty-test-recovery-admin-secret-2026-value";

    private readonly FastyApiFactory _factory;

    public PasswordRecoveryAdminIntegrationTests(
        FastyApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Recovery_admin_endpoint_is_hidden_when_disabled()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/admin/password-recovery-credentials",
                new
                {
                    email = "missing@example.com"
                });

        Assert.Equal(
            HttpStatusCode.NotFound,
            response.StatusCode);
    }

    [Fact]
    public async Task Recovery_admin_endpoint_rejects_missing_or_wrong_secret()
    {
        await _factory.ResetStorageAsync();

        using var factory =
            CreateEnabledFactory();

        using var client =
            factory.CreateClient();

        using var missingResponse =
            await client.PostAsJsonAsync(
                "/api/auth/admin/password-recovery-credentials",
                new
                {
                    email = "person@example.com"
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            missingResponse.StatusCode);

        using var wrongRequest =
            new HttpRequestMessage(
                HttpMethod.Post,
                "/api/auth/admin/password-recovery-credentials")
            {
                Content =
                    JsonContent.Create(
                        new
                        {
                            email = "person@example.com"
                        })
            };

        wrongRequest.Headers.Add(
            AdminHeader,
            "definitely-the-wrong-secret");

        using var wrongResponse =
            await client.SendAsync(
                wrongRequest);

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            wrongResponse.StatusCode);
    }

    [Fact]
    public async Task Recovery_admin_issues_raw_credential_but_stores_only_hash()
    {
        await _factory.ResetStorageAsync();

        const string email =
            "recovery-admin-success@example.com";

        using var authenticatedClient =
            await _factory.CreateAuthenticatedClientAsync(
                email);

        using var factory =
            CreateEnabledFactory();

        using var client =
            factory.CreateClient();

        using var request =
            CreateIssueRequest(email);

        using var response =
            await client.SendAsync(
                request);

        Assert.Equal(
            HttpStatusCode.OK,
            response.StatusCode);

        var body =
            await response.Content
                .ReadFromJsonAsync<JsonElement>();

        var rawCredential =
            body
                .GetProperty("recoveryCredential")
                .GetString();

        var expiresAt =
            body
                .GetProperty("expiresAt")
                .GetDateTimeOffset();

        Assert.False(
            string.IsNullOrWhiteSpace(
                rawCredential));

        Assert.True(
            rawCredential!.Length >= 40);

        Assert.True(
            expiresAt >
            DateTimeOffset.UtcNow.AddMinutes(20));

        var storedHash =
            await _factory.ExecuteScalarAsync<string>(
                """
                SELECT "TokenHash"
                FROM auth.password_recovery_credentials
                WHERE "UserId" =
                (
                    SELECT "Id"
                    FROM auth.users
                    WHERE "NormalizedEmail" = @email
                )
                ORDER BY "CreatedAt" DESC
                LIMIT 1;
                """,
                new Npgsql.NpgsqlParameter(
                    "email",
                    email.ToUpperInvariant()));

        Assert.NotEqual(
            rawCredential,
            storedHash);

        var expectedHash =
            Convert.ToHexString(
                System.Security.Cryptography.SHA256.HashData(
                    System.Text.Encoding.UTF8.GetBytes(
                        rawCredential)));

        Assert.Equal(
            expectedHash,
            storedHash);
    }

    [Fact]
    public async Task Issuing_new_recovery_credential_closes_previous_active_one()
    {
        await _factory.ResetStorageAsync();

        const string email =
            "recovery-admin-replace@example.com";

        using var authenticatedClient =
            await _factory.CreateAuthenticatedClientAsync(
                email);

        using var factory =
            CreateEnabledFactory();

        using var client =
            factory.CreateClient();

        using var firstRequest =
            CreateIssueRequest(email);

        using var firstResponse =
            await client.SendAsync(
                firstRequest);

        firstResponse.EnsureSuccessStatusCode();

        using var secondRequest =
            CreateIssueRequest(email);

        using var secondResponse =
            await client.SendAsync(
                secondRequest);

        secondResponse.EnsureSuccessStatusCode();

        var totalCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.password_recovery_credentials
                WHERE "UserId" =
                (
                    SELECT "Id"
                    FROM auth.users
                    WHERE "NormalizedEmail" = @email
                );
                """,
                new Npgsql.NpgsqlParameter(
                    "email",
                    email.ToUpperInvariant()));

        var activeCount =
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
                AND "ConsumedAt" IS NULL
                AND "ExpiresAt" > CURRENT_TIMESTAMP;
                """,
                new Npgsql.NpgsqlParameter(
                    "email",
                    email.ToUpperInvariant()));

        Assert.Equal(
            2,
            totalCount);

        Assert.Equal(
            1,
            activeCount);
    }

    [Fact]
    public async Task Recovery_admin_returns_not_found_for_unknown_user()
    {
        await _factory.ResetStorageAsync();

        using var factory =
            CreateEnabledFactory();

        using var client =
            factory.CreateClient();

        using var request =
            CreateIssueRequest(
                "unknown-recovery-user@example.com");

        using var response =
            await client.SendAsync(
                request);

        Assert.Equal(
            HttpStatusCode.NotFound,
            response.StatusCode);
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

    private static HttpRequestMessage CreateIssueRequest(
        string email)
    {
        var request =
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

        return request;
    }
}
