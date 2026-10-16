using Fasty.Api.Modules.Identity.Google;

namespace Fasty.Api.Tests;

public sealed class TestGoogleAuthorizationCodeExchanger
    : IGoogleAuthorizationCodeExchanger
{
    public bool IsConfigured { get; set; } = true;

    public string? LastCode { get; private set; }

    public string? LastCodeVerifier { get; private set; }

    public string? LastRedirectUri { get; private set; }

    public Task<string?> ExchangeAsync(
        string code,
        string codeVerifier,
        string redirectUri,
        CancellationToken cancellationToken)
    {
        LastCode = code;
        LastCodeVerifier = codeVerifier;
        LastRedirectUri = redirectUri;

        var idToken =
            code == "valid-desktop-code"
                ? "google-new-user"
                : null;

        return Task.FromResult(idToken);
    }

    public void Reset()
    {
        IsConfigured = true;
        LastCode = null;
        LastCodeVerifier = null;
        LastRedirectUri = null;
    }
}
