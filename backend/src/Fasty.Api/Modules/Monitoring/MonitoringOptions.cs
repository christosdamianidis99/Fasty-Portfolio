namespace Fasty.Api.Modules.Monitoring;

public sealed class MonitoringOptions
{
    public const string SectionName = "Monitoring";

    public bool Enabled { get; init; }

    public int RequestCapacity { get; init; } = 10_000;

    public int ActionCapacity { get; init; } = 10_000;

    public string AnonymizationKey { get; init; } = string.Empty;

    public string SnapshotImportFile { get; init; } =
        string.Empty;

    public bool ArchivePlanningEnabled { get; init; }

    public int RetentionDays { get; init; } = 90;

    public string ArchiveDirectory { get; init; } =
        string.Empty;
}
