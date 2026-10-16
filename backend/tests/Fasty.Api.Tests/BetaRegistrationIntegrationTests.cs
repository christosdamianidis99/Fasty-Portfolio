using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace Fasty.Api.Tests;

public sealed class BetaRegistrationIntegrationTests
    : IClassFixture<FastyApiFactory>
{
    private readonly FastyApiFactory _factory;

    public BetaRegistrationIntegrationTests(
        FastyApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Beta_user_can_register_login_and_refresh_without_email()
    {
        await _factory.ResetStorageAsync();

        using var betaFactory =
            _factory.WithWebHostBuilder(builder =>
            {
                builder.ConfigureAppConfiguration(
                    (_, configuration) =>
                    {
                        configuration.AddInMemoryCollection(
                            new Dictionary<string, string?>
                            {
                                ["Authentication:Registration:Enabled"] =
                                    "true",
                                ["Authentication:Registration:RequireEmailVerification"] =
                                    "false",
                                ["Email:Delivery:Enabled"] =
                                    "false"
                            });
                    });
            });

        using var client = betaFactory.CreateClient();

        const string email = "beta-flow@example.com";
        const string password = "StrongPassword123!";

        using var registrationResponse =
            await client.PostAsJsonAsync(
                "/api/auth/register",
                new
                {
                    email,
                    password
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            registrationResponse.StatusCode);

        var emailConfirmed =
            await _factory.ExecuteScalarAsync<bool>(
                """
                SELECT "EmailConfirmed"
                FROM auth.users
                WHERE "NormalizedEmail" = 'BETA-FLOW@EXAMPLE.COM'
                """);

        Assert.True(emailConfirmed);

        using var loginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password,
                    deviceName = "Fasty beta integration test"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            loginResponse.StatusCode);

        var loginBody =
            await loginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var refreshToken =
            loginBody.GetProperty("refreshToken")
                .GetString();

        Assert.False(
            string.IsNullOrWhiteSpace(refreshToken));

        using var refreshResponse =
            await client.PostAsJsonAsync(
                "/api/auth/refresh",
                new
                {
                    refreshToken
                });

        Assert.Equal(
            HttpStatusCode.OK,
            refreshResponse.StatusCode);
    }
}
