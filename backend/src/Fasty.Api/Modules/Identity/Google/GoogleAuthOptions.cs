namespace Fasty.Api.Modules.Identity.Google;

public sealed class GoogleAuthOptions
{
    public const string SectionName =
        "Authentication:Google";

    public bool Enabled { get; set; }

    public string[] ClientIds { get; set; } = [];

    public string DesktopClientId { get; set; } = string.Empty;

    public string DesktopClientSecret { get; set; } = string.Empty;
}
