using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Fasty.Api.Modules.Identity;
using Fasty.Api.Modules.Identity.Tokens;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Fasty.Api.Tests;

public sealed class GoogleLinkIntegrationTests
    : IClassFixture<FastyApiFactory>
{
    private readonly FastyApiFactory _factory;

    public GoogleLinkIntegrationTests(
        FastyApiFactory factory)
    {
        _factory =
            factory;
    }

    [Fact]
    public async Task Authenticated_user_can_link_matching_Google_account()
    {
        await _factory.ResetStorageAsync();

        var user =
            await CreateUserAsync(
                "link-existing@example.com");

        using var client =
            CreateAuthenticatedClient(
                user);

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/google/link",
                new
                {
                    idToken =
                        "google-link-existing"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            response.StatusCode);

        var loginCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.user_logins
                WHERE "LoginProvider" = 'Google'
                  AND "ProviderKey" =
                      'google-sub-link-existing'
                  AND "UserId" = (
                      SELECT "Id"
                      FROM auth.users
                      WHERE "Email" =
                          'link-existing@example.com'
                  );
                """);

        Assert.Equal(
            1,
            loginCount);
    }

    [Fact]
    public async Task Google_link_status_reflects_account_linking()
    {
        await _factory.ResetStorageAsync();
        var user = await CreateUserAsync("link-existing@example.com");
        using var client = CreateAuthenticatedClient(user);

        using var before = await client.GetAsync("/api/auth/google/link");
        Assert.Equal(HttpStatusCode.OK, before.StatusCode);
        Assert.False((await before.Content.ReadFromJsonAsync<GoogleLinkStatus>())!.Linked);

        using var link = await client.PostAsJsonAsync(
            "/api/auth/google/link",
            new { idToken = "google-link-existing" });
        Assert.Equal(HttpStatusCode.OK, link.StatusCode);

        using var after = await client.GetAsync("/api/auth/google/link");
        Assert.Equal(HttpStatusCode.OK, after.StatusCode);
        Assert.True((await after.Content.ReadFromJsonAsync<GoogleLinkStatus>())!.Linked);
    }

    private sealed record GoogleLinkStatus(bool Linked);

    [Fact]
    public async Task Linking_same_Google_account_twice_is_idempotent()
    {
        await _factory.ResetStorageAsync();

        var user =
            await CreateUserAsync(
                "link-existing@example.com");

        using var client =
            CreateAuthenticatedClient(
                user);

        for (var attempt = 0;
             attempt < 2;
             attempt++)
        {
            using var response =
                await client.PostAsJsonAsync(
                    "/api/auth/google/link",
                    new
                    {
                        idToken =
                            "google-link-existing"
                    });

            Assert.Equal(
                HttpStatusCode.OK,
                response.StatusCode);
        }

        var loginCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.user_logins
                WHERE "LoginProvider" = 'Google'
                  AND "ProviderKey" =
                      'google-sub-link-existing';
                """);

        Assert.Equal(
            1,
            loginCount);
    }

    [Fact]
    public async Task Linking_Google_account_with_different_email_is_rejected()
    {
        await _factory.ResetStorageAsync();

        var user =
            await CreateUserAsync(
                "link-existing@example.com");

        using var client =
            CreateAuthenticatedClient(
                user);

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/google/link",
                new
                {
                    idToken =
                        "google-link-mismatch"
                });

        Assert.Equal(
            HttpStatusCode.Conflict,
            response.StatusCode);

        var loginCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.user_logins
                WHERE "ProviderKey" =
                    'google-sub-link-mismatch';
                """);

        Assert.Equal(
            0,
            loginCount);
    }

    [Fact]
    public async Task Google_identity_linked_to_another_user_is_rejected()
    {
        await _factory.ResetStorageAsync();

        var owner =
            await CreateUserAsync(
                "owner@example.com");

        var currentUser =
            await CreateUserAsync(
                "link-existing@example.com");

        using (
            var scope =
                _factory.Services.CreateScope())
        {
            var userManager =
                scope.ServiceProvider
                    .GetRequiredService<
                        UserManager<ApplicationUser>>();

            var trackedOwner =
                await userManager.FindByIdAsync(
                    owner.Id.ToString());

            Assert.NotNull(
                trackedOwner);

            var result =
                await userManager.AddLoginAsync(
                    trackedOwner,
                    new UserLoginInfo(
                        "Google",
                        "google-sub-owned-by-other",
                        "Google"));

            Assert.True(
                result.Succeeded);
        }

        using var client =
            CreateAuthenticatedClient(
                currentUser);

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/google/link",
                new
                {
                    idToken =
                        "google-owned-by-other"
                });

        Assert.Equal(
            HttpStatusCode.Conflict,
            response.StatusCode);

        var linkedUserEmail =
            await _factory.ExecuteScalarAsync<string>(
                """
                SELECT u."Email"
                FROM auth.user_logins l
                INNER JOIN auth.users u
                    ON u."Id" = l."UserId"
                WHERE l."LoginProvider" = 'Google'
                  AND l."ProviderKey" =
                      'google-sub-owned-by-other';
                """);

        Assert.Equal(
            "owner@example.com",
            linkedUserEmail);
    }

    [Fact]
    public async Task Invalid_Google_identity_is_rejected_for_linking()
    {
        await _factory.ResetStorageAsync();

        var user =
            await CreateUserAsync(
                "link-existing@example.com");

        using var client =
            CreateAuthenticatedClient(
                user);

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/google/link",
                new
                {
                    idToken =
                        "invalid-google-token"
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            response.StatusCode);
    }

    [Fact]
    public async Task Google_link_requires_authentication()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/google/link",
                new
                {
                    idToken =
                        "google-link-existing"
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            response.StatusCode);
    }

    private async Task<ApplicationUser> CreateUserAsync(
        string email)
    {
        using var scope =
            _factory.Services.CreateScope();

        var userManager =
            scope.ServiceProvider
                .GetRequiredService<
                    UserManager<ApplicationUser>>();

        var user =
            new ApplicationUser
            {
                Id = Guid.NewGuid(),
                UserName = email,
                Email = email,
                EmailConfirmed = false,
                CreatedAt = DateTimeOffset.UtcNow
            };

        var result =
            await userManager.CreateAsync(
                user,
                "Existing-Test-Password-123!");

        Assert.True(
            result.Succeeded);

        return user;
    }

    private HttpClient CreateAuthenticatedClient(
        ApplicationUser user)
    {
        using var scope =
            _factory.Services.CreateScope();

        var accessTokenService =
            scope.ServiceProvider
                .GetRequiredService<
                    IAccessTokenService>();

        var accessToken =
            accessTokenService.Generate(
                user,
                DateTimeOffset.UtcNow);

        var client =
            _factory.CreateClient();

        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue(
                "Bearer",
                accessToken.Token);

        return client;
    }
}
