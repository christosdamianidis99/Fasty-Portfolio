using System.Text.Json;
using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Identity.Google;

public interface IGoogleAuthorizationCodeExchanger
{
    bool IsConfigured { get; }

    Task<string?> ExchangeAsync(
        string code,
        string codeVerifier,
        string redirectUri,
        CancellationToken cancellationToken);
}

public sealed class GoogleAuthorizationCodeExchanger
    : IGoogleAuthorizationCodeExchanger
{
    private readonly HttpClient _httpClient;
    private readonly GoogleAuthOptions _options;

    public GoogleAuthorizationCodeExchanger(
        HttpClient httpClient,
        IOptions<GoogleAuthOptions> optionsAccessor)
    {
        _httpClient = httpClient;
        _options = optionsAccessor.Value;
    }

    public bool IsConfigured =>
        _options.Enabled
        && !string.IsNullOrWhiteSpace(
            _options.DesktopClientId)
        && !string.IsNullOrWhiteSpace(
            _options.DesktopClientSecret);

    public async Task<string?> ExchangeAsync(
        string code,
        string codeVerifier,
        string redirectUri,
        CancellationToken cancellationToken)
    {
        if (!IsConfigured)
        {
            return null;
        }

        using var content =
            new FormUrlEncodedContent(
                new Dictionary<string, string>
                {
                    ["client_id"] =
                        _options.DesktopClientId.Trim(),
                    ["client_secret"] =
                        _options.DesktopClientSecret.Trim(),
                    ["code"] =
                        code.Trim(),
                    ["code_verifier"] =
                        codeVerifier.Trim(),
                    ["grant_type"] =
                        "authorization_code",
                    ["redirect_uri"] =
                        redirectUri.Trim()
                });

        using var response =
            await _httpClient.PostAsync(
                "token",
                content,
                cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        await using var stream =
            await response.Content.ReadAsStreamAsync(
                cancellationToken);

        using var document =
            await JsonDocument.ParseAsync(
                stream,
                cancellationToken:
                    cancellationToken);

        if (!document.RootElement.TryGetProperty(
                "id_token",
                out var idTokenElement)
            || idTokenElement.ValueKind
                != JsonValueKind.String)
        {
            return null;
        }

        var idToken =
            idTokenElement.GetString();

        return string.IsNullOrWhiteSpace(idToken)
            ? null
            : idToken;
    }
}
