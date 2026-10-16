namespace Fasty.Api.Modules.Releases;

public sealed class ReleaseAnnouncementOptions
{
    public const string SectionName = "ReleaseAnnouncement";

    public bool Enabled { get; set; }

    public string Id { get; set; } = string.Empty;

    public string Title { get; set; } = string.Empty;

    public string Message { get; set; } = string.Empty;

    public string? ContactUrl { get; set; }
}
