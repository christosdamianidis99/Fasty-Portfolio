using System.Text.Json;
using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Monitoring;

public sealed class AnalyticsSnapshotImporter
{
    private readonly IUserActionStore _store;
    private readonly MonitoringOptions _options;
    private readonly ILogger<AnalyticsSnapshotImporter>
        _logger;

    public AnalyticsSnapshotImporter(
        IUserActionStore store,
        IOptions<MonitoringOptions> optionsAccessor,
        ILogger<AnalyticsSnapshotImporter> logger)
    {
        _store = store;
        _options = optionsAccessor.Value;
        _logger = logger;
    }

    public async Task ImportConfiguredSnapshotAsync(
        CancellationToken cancellationToken = default)
    {
        var importFile =
            _options.SnapshotImportFile?.Trim();

        if (string.IsNullOrWhiteSpace(importFile))
        {
            return;
        }

        if (!File.Exists(importFile))
        {
            _logger.LogWarning(
                "Configured analytics snapshot does not exist: {ImportFile}",
                importFile);

            return;
        }

        await using var stream =
            File.OpenRead(importFile);

        var events =
            await JsonSerializer.DeserializeAsync<
                List<UserActionMetric>>(
                stream,
                new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                },
                cancellationToken)
            ?? [];

        var imported = 0;

        foreach (var metric in events)
        {
            await _store.AddAsync(
                metric,
                cancellationToken);

            imported++;
        }

        _logger.LogInformation(
            "Processed {EventCount} analytics snapshot events from {ImportFile}.",
            imported,
            importFile);
    }
}
