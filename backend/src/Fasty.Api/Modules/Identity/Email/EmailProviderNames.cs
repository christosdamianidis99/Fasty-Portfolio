namespace Fasty.Api.Modules.Identity.Email;

public static class EmailProviderNames
{
    public const string Resend =
        "Resend";

    public const string Smtp =
        "Smtp";

    public static bool IsSupported(
        string? provider)
    {
        return string.Equals(
                provider,
                Resend,
                StringComparison.OrdinalIgnoreCase)
            || string.Equals(
                provider,
                Smtp,
                StringComparison.OrdinalIgnoreCase);
    }
}