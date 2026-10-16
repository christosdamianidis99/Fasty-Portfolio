using Microsoft.Extensions.Options;
using Npgsql;

namespace Fasty.Api.Modules.Monitoring;

public sealed class AnalyticsArchivePlanner(
    IConfiguration configuration,
    IOptions<MonitoringOptions> options,
    ILogger<AnalyticsArchivePlanner> logger)
{
    private readonly MonitoringOptions _options =
        options.Value;

    public async Task<AnalyticsArchivePlan?> PlanAsync(
        CancellationToken cancellationToken = default)
    {
        if (!_options.ArchivePlanningEnabled)
        {
            logger.LogInformation(
                "Analytics archive planning is disabled.");

            return null;
        }

        var connectionString =
            configuration.GetConnectionString(
                "FastyDatabase");

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException(
                "The FastyDatabase connection string is not configured.");
        }

        var cutoffUtc =
            DateTimeOffset.UtcNow.AddDays(
                -_options.RetentionDays);

        await using var connection =
            new NpgsqlConnection(connectionString);

        await connection.OpenAsync(cancellationToken);

        await using var command =
            connection.CreateCommand();

        command.CommandText = """
            SELECT
                COUNT(*)::bigint,
                MIN(timestamp_utc),
                MAX(timestamp_utc)
            FROM analytics.user_actions
            WHERE timestamp_utc < @cutoff_utc;
            """;

        command.Parameters.AddWithValue(
            "cutoff_utc",
            cutoffUtc);

        await using var reader =
            await command.ExecuteReaderAsync(
                cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException(
                "The analytics archive planning query returned no result.");
        }

        var eligibleRowCount =
            reader.GetInt64(0);

        DateTimeOffset? oldestEligibleUtc = null;
        DateTimeOffset? newestEligibleUtc = null;

        if (!reader.IsDBNull(1))
        {
            oldestEligibleUtc =
                new DateTimeOffset(
                    DateTime.SpecifyKind(
                        reader.GetDateTime(1),
                        DateTimeKind.Utc));
        }

        if (!reader.IsDBNull(2))
        {
            newestEligibleUtc =
                new DateTimeOffset(
                    DateTime.SpecifyKind(
                        reader.GetDateTime(2),
                        DateTimeKind.Utc));
        }

        var plan =
            new AnalyticsArchivePlan(
                cutoffUtc,
                eligibleRowCount,
                oldestEligibleUtc,
                newestEligibleUtc);

        logger.LogInformation(
            "Analytics archive dry-run: {EligibleRowCount} rows are older than {CutoffUtc}. Oldest eligible: {OldestEligibleUtc}; newest eligible: {NewestEligibleUtc}. No files were created and no rows were deleted.",
            plan.EligibleRowCount,
            plan.CutoffUtc,
            plan.OldestEligibleUtc,
            plan.NewestEligibleUtc);

        return plan;
    }
}

public sealed record AnalyticsArchivePlan(
    DateTimeOffset CutoffUtc,
    long EligibleRowCount,
    DateTimeOffset? OldestEligibleUtc,
    DateTimeOffset? NewestEligibleUtc);
