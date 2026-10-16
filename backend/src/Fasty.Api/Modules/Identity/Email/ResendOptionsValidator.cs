using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Identity.Email;

public sealed class ResendOptionsValidator
    : IValidateOptions<ResendOptions>
{
    public ValidateOptionsResult Validate(
        string? name,
        ResendOptions options)
    {
        if (string.IsNullOrWhiteSpace(
            options.ApiKey))
        {
            return ValidateOptionsResult.Fail(
                "Email:Resend:ApiKey is required " +
                "when Resend email delivery is enabled.");
        }

        return ValidateOptionsResult.Success;
    }
}
