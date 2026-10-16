using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Identity.Email;

public sealed class SmtpOptionsValidator
    : IValidateOptions<SmtpOptions>
{
    public ValidateOptionsResult Validate(
        string? name,
        SmtpOptions options)
    {
        var failures = new List<string>();

        if (string.IsNullOrWhiteSpace(
                options.Host))
        {
            failures.Add(
                "Email:Smtp:Host is required when SMTP email delivery is enabled.");
        }

        if (options.Port is < 1 or > 65535)
        {
            failures.Add(
                "Email:Smtp:Port must be between 1 and 65535.");
        }

        if (string.IsNullOrWhiteSpace(
                options.Username))
        {
            failures.Add(
                "Email:Smtp:Username is required when SMTP email delivery is enabled.");
        }

        if (string.IsNullOrWhiteSpace(
                options.Password))
        {
            failures.Add(
                "Email:Smtp:Password is required when SMTP email delivery is enabled.");
        }

        return failures.Count == 0
            ? ValidateOptionsResult.Success
            : ValidateOptionsResult.Fail(
                failures);
    }
}