using Google.Apis.Auth;
using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Identity.Google;

public interface IGoogleIdentityTokenValidator
{
    bool IsConfigured { get; }

    Task<GoogleIdentity?> ValidateAsync(
        string idToken);
}

public sealed class GoogleIdentityTokenValidator
    : IGoogleIdentityTokenValidator
{
    private readonly GoogleAuthOptions _options;

    public GoogleIdentityTokenValidator(
        IOptions<GoogleAuthOptions> optionsAccessor)
    {
        _options =
            optionsAccessor.Value;
    }

    public bool IsConfigured =>
        _options.Enabled
        && _options.ClientIds.Any(
            clientId =>
                !string.IsNullOrWhiteSpace(clientId));

    public async Task<GoogleIdentity?> ValidateAsync(
        string idToken)
    {
        if (!IsConfigured
            || string.IsNullOrWhiteSpace(idToken))
        {
            return null;
        }

        try
        {
            var settings =
                new GoogleJsonWebSignature.ValidationSettings
                {
                    Audience =
                        _options.ClientIds
                            .Where(
                                clientId =>
                                    !string.IsNullOrWhiteSpace(
                                        clientId))
                            .Select(
                                clientId =>
                                    clientId.Trim())
                            .Distinct(
                                StringComparer.Ordinal)
                            .ToArray()
                };

            var payload =
                await GoogleJsonWebSignature.ValidateAsync(
                    idToken.Trim(),
                    settings);

            if (string.IsNullOrWhiteSpace(payload.Subject)
                || string.IsNullOrWhiteSpace(payload.Email))
            {
                return null;
            }

            return new GoogleIdentity(
                payload.Subject,
                payload.Email.Trim(),
                payload.EmailVerified,
                string.IsNullOrWhiteSpace(
                    payload.HostedDomain)
                    ? null
                    : payload.HostedDomain.Trim());
        }
        catch
        {
            return null;
        }
    }
}
