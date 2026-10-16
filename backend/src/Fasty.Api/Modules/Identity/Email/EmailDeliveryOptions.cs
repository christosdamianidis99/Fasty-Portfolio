namespace Fasty.Api.Modules.Identity.Email;

public sealed class EmailDeliveryOptions
{
    public const string SectionName =
        "Email:Delivery";

    public bool Enabled { get; init; }

    public string Provider { get; init; } =
        EmailProviderNames.Resend;

    public string FromAddress { get; init; } =
        string.Empty;

    public string FromName { get; init; } =
        "Fasty";

    public string ConfirmationUrl { get; init; } =
        string.Empty;

    public string PasswordResetUrl { get; init; } =
        string.Empty;
}
