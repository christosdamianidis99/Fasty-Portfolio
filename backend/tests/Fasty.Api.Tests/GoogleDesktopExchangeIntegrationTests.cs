using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Xunit;

namespace Fasty.Api.Tests;

public sealed class GoogleDesktopExchangeIntegrationTests
    : IClassFixture<FastyApiFactory>
{
    private readonly FastyApiFactory _factory;

    public GoogleDesktopExchangeIntegrationTests(
        FastyApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Valid_loopback_exchange_returns_ID_token()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/google/desktop/exchange",
                new
                {
                    code =
                        "valid-desktop-code",
                    codeVerifier =
                        "desktop-pkce-verifier",
                    redirectUri =
                        "http://127.0.0.1:49152/"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            response.StatusCode);

        using var body =
            await response.Content
                .ReadFromJsonAsync<JsonDocument>();

        Assert.NotNull(body);

        Assert.Equal(
            "google-new-user",
            body.RootElement
                .GetProperty("idToken")
                .GetString());

        Assert.Equal(
            "valid-desktop-code",
            _factory
                .GoogleAuthorizationCodeExchanger
                .LastCode);

        Assert.Equal(
            "desktop-pkce-verifier",
            _factory
                .GoogleAuthorizationCodeExchanger
                .LastCodeVerifier);

        Assert.Equal(
            "http://127.0.0.1:49152/",
            _factory
                .GoogleAuthorizationCodeExchanger
                .LastRedirectUri);
    }

    [Theory]
    [InlineData("http://localhost:49152/")]
    [InlineData("https://127.0.0.1:49152/")]
    [InlineData("http://127.0.0.1:49152/callback")]
    [InlineData("http://127.0.0.1:49152/?code=value")]
    public async Task Invalid_redirect_URI_is_rejected(
        string redirectUri)
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/google/desktop/exchange",
                new
                {
                    code =
                        "valid-desktop-code",
                    codeVerifier =
                        "desktop-pkce-verifier",
                    redirectUri
                });

        Assert.Equal(
            HttpStatusCode.BadRequest,
            response.StatusCode);

        Assert.Null(
            _factory
                .GoogleAuthorizationCodeExchanger
                .LastCode);
    }

    [Fact]
    public async Task Failed_Google_exchange_is_unauthorized()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/google/desktop/exchange",
                new
                {
                    code =
                        "invalid-desktop-code",
                    codeVerifier =
                        "desktop-pkce-verifier",
                    redirectUri =
                        "http://127.0.0.1:49152/"
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            response.StatusCode);
    }

    [Fact]
    public async Task Unconfigured_desktop_exchange_is_not_found()
    {
        await _factory.ResetStorageAsync();

        _factory
            .GoogleAuthorizationCodeExchanger
            .IsConfigured = false;

        using var client =
            _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/google/desktop/exchange",
                new
                {
                    code =
                        "valid-desktop-code",
                    codeVerifier =
                        "desktop-pkce-verifier",
                    redirectUri =
                        "http://127.0.0.1:49152/"
                });

        Assert.Equal(
            HttpStatusCode.NotFound,
            response.StatusCode);
    }
}
