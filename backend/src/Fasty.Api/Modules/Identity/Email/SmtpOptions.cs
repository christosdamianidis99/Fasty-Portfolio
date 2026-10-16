namespace Fasty.Api.Modules.Identity.Email;

public sealed class SmtpOptions
{
    public const string SectionName =
        "Email:Smtp";

    public string Host { get; init; } =
        string.Empty;

    public int Port { get; init; } =
        587;

    public string Username { get; init; } =
        string.Empty;

    public string Password { get; init; } =
        string.Empty;

    public bool UseStartTls { get; init; } =
        true;
}