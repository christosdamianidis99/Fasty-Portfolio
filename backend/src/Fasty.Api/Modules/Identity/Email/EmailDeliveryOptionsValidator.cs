using System.Net.Mail;
using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Identity.Email;

public sealed class EmailDeliveryOptionsValidator
    : IValidateOptions<EmailDeliveryOptions>
{
    private const string AppScheme = "fasty";
    private const string AppHost = "account";
    private const string ConfirmationPath = "/confirm-email";
    private const string PasswordResetPath = "/reset-password";

    public ValidateOptionsResult Validate(
        string? name,
        EmailDeliveryOptions options)
    {
        if (!options.Enabled)
        {
            return ValidateOptionsResult.Success;
        }

        var failures = new List<string>();

        if (!EmailProviderNames.IsSupported(
                options.Provider))
        {
            failures.Add(
                "Email delivery provider must be Resend or Smtp.");
        }

        if (!IsValidEmailAddress(options.FromAddress))
        {
            failures.Add(
                "Email sender address must be a valid email address.");
        }

        if (string.IsNullOrWhiteSpace(options.FromName))
        {
            failures.Add(
                "Email sender name is required.");
        }

        if (!IsValidAccountActionUrl(
                options.ConfirmationUrl,
                ConfirmationPath))
        {
            failures.Add(
                "Email confirmation URL must be an absolute HTTP/HTTPS URL or fasty://account/confirm-email.");
        }

        if (!IsValidAccountActionUrl(
                options.PasswordResetUrl,
                PasswordResetPath))
        {
            failures.Add(
                "Password reset URL must be an absolute HTTP/HTTPS URL or fasty://account/reset-password.");
        }

        return failures.Count == 0
            ? ValidateOptionsResult.Success
            : ValidateOptionsResult.Fail(failures);
    }

    private static bool IsValidEmailAddress(
        string address)
    {
        if (string.IsNullOrWhiteSpace(address))
        {
            return false;
        }

        try
        {
            var parsed = new MailAddress(address);

            return string.Equals(
                parsed.Address,
                address,
                StringComparison.OrdinalIgnoreCase);
        }
        catch (FormatException)
        {
            return false;
        }
    }

    private static bool IsValidAccountActionUrl(
        string url,
        string expectedPath)
    {
        if (!Uri.TryCreate(
                url,
                UriKind.Absolute,
                out var uri))
        {
            return false;
        }

        if (string.Equals(
                uri.Scheme,
                Uri.UriSchemeHttp,
                StringComparison.OrdinalIgnoreCase)
            || string.Equals(
                uri.Scheme,
                Uri.UriSchemeHttps,
                StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return string.Equals(
                uri.Scheme,
                AppScheme,
                StringComparison.OrdinalIgnoreCase)
            && string.Equals(
                uri.Host,
                AppHost,
                StringComparison.OrdinalIgnoreCase)
            && string.Equals(
                uri.AbsolutePath,
                expectedPath,
                StringComparison.Ordinal)
            && string.IsNullOrEmpty(uri.Query)
            && string.IsNullOrEmpty(uri.Fragment)
            && string.IsNullOrEmpty(uri.UserInfo)
            && uri.IsDefaultPort;
    }
}
