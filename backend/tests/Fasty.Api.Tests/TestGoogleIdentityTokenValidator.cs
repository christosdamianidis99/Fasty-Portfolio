using Fasty.Api.Modules.Identity.Google;

namespace Fasty.Api.Tests;

public sealed class TestGoogleIdentityTokenValidator
    : IGoogleIdentityTokenValidator
{
    public bool IsConfigured =>
        true;

    public Task<GoogleIdentity?> ValidateAsync(
        string idToken)
    {
        GoogleIdentity? identity =
            idToken switch
            {
                "google-new-user" =>
                    new GoogleIdentity(
                        "google-sub-new-user",
                        "google-new@example.com",
                        true,
                        null),

                "google-existing-email" =>
                    new GoogleIdentity(
                        "google-sub-existing-email",
                        "existing-google@example.com",
                        true,
                        null),

                "google-unverified" =>
                    new GoogleIdentity(
                        "google-sub-unverified",
                        "unverified-google@example.com",
                        false,
                        null),

                "google-link-existing" =>
                    new GoogleIdentity(
                        "google-sub-link-existing",
                        "link-existing@example.com",
                        true,
                        null),

                "google-link-mismatch" =>
                    new GoogleIdentity(
                        "google-sub-link-mismatch",
                        "different-google@example.com",
                        true,
                        null),

                "google-owned-by-other" =>
                    new GoogleIdentity(
                        "google-sub-owned-by-other",
                        "link-existing@example.com",
                        true,
                        null),

                _ =>
                    null
            };

        return Task.FromResult(
            identity);
    }
}
