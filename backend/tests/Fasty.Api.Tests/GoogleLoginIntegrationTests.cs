using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Fasty.Api.Modules.Identity;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Fasty.Api.Tests;

public sealed class GoogleLoginIntegrationTests
    : IClassFixture<FastyApiFactory>
{
    private readonly FastyApiFactory _factory;

    public GoogleLoginIntegrationTests(
        FastyApiFactory factory)
    {
        _factory =
            factory;
    }

    [Fact]
    public async Task Google_login_creates_new_user_and_external_login()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/google",
                new
                {
                    idToken =
                        "google-new-user",
                    deviceName =
                        "Google test device"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            response.StatusCode);

        using var responseBody =
            await response.Content
                .ReadFromJsonAsync<JsonDocument>();

        Assert.NotNull(
            responseBody);

        Assert.Equal(
            "google-new@example.com",
            responseBody.RootElement
                .GetProperty("email")
                .GetString());

        var userCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.users
                WHERE "Email" = 'google-new@example.com';
                """);

        Assert.Equal(
            1,
            userCount);

        var loginCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.user_logins
                WHERE "LoginProvider" = 'Google'
                  AND "ProviderKey" = 'google-sub-new-user';
                """);

        Assert.Equal(
            1,
            loginCount);
    }

    [Fact]
    public async Task Repeated_Google_login_reuses_same_Fasty_account()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        for (var attempt = 0;
             attempt < 2;
             attempt++)
        {
            using var response =
                await client.PostAsJsonAsync(
                    "/api/auth/google",
                    new
                    {
                        idToken =
                            "google-new-user",
                        deviceName =
                            $"Google device {attempt}"
                    });

            Assert.Equal(
                HttpStatusCode.OK,
                response.StatusCode);
        }

        var userCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.users
                WHERE "Email" = 'google-new@example.com';
                """);

        Assert.Equal(
            1,
            userCount);

        var loginCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.user_logins
                WHERE "LoginProvider" = 'Google'
                  AND "ProviderKey" = 'google-sub-new-user';
                """);

        Assert.Equal(
            1,
            loginCount);
    }

    [Fact]
    public async Task Existing_email_requires_explicit_linking()
    {
        await _factory.ResetStorageAsync();

        using (
            var scope =
                _factory.Services.CreateScope())
        {
            var userManager =
                scope.ServiceProvider
                    .GetRequiredService<
                        UserManager<ApplicationUser>>();

            var user =
                new ApplicationUser
                {
                    Id = Guid.NewGuid(),
                    UserName =
                        "existing-google@example.com",
                    Email =
                        "existing-google@example.com",
                    EmailConfirmed =
                        false,
                    CreatedAt =
                        DateTimeOffset.UtcNow
                };

            var result =
                await userManager.CreateAsync(
                    user,
                    "Existing-Test-Password-123!");

            Assert.True(
                result.Succeeded);
        }

        using var client =
            _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/google",
                new
                {
                    idToken =
                        "google-existing-email",
                    deviceName =
                        "Existing account test"
                });

        Assert.Equal(
            HttpStatusCode.Conflict,
            response.StatusCode);

        using var responseBody =
            await response.Content
                .ReadFromJsonAsync<JsonDocument>();

        Assert.NotNull(
            responseBody);

        Assert.Equal(
            "account_link_required",
            responseBody.RootElement
                .GetProperty("code")
                .GetString());

        var loginCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.user_logins
                WHERE "LoginProvider" = 'Google'
                  AND "ProviderKey" =
                      'google-sub-existing-email';
                """);

        Assert.Equal(
            0,
            loginCount);
    }

    [Fact]
    public async Task Invalid_or_unverified_Google_identity_is_rejected()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var invalidResponse =
            await client.PostAsJsonAsync(
                "/api/auth/google",
                new
                {
                    idToken =
                        "invalid-google-token",
                    deviceName =
                        "Invalid Google test"
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            invalidResponse.StatusCode);

        using var unverifiedResponse =
            await client.PostAsJsonAsync(
                "/api/auth/google",
                new
                {
                    idToken =
                        "google-unverified",
                    deviceName =
                        "Unverified Google test"
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            unverifiedResponse.StatusCode);

        var userCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.users;
                """);

        Assert.Equal(
            0,
            userCount);
    }
}
