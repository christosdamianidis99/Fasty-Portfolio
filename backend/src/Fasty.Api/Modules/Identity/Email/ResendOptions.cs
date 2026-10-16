namespace Fasty.Api.Modules.Identity.Email;

public sealed class ResendOptions
{
    public const string SectionName =
        "Email:Resend";

    public string ApiKey { get; init; } =
        string.Empty;
}
