using Npgsql;
using NpgsqlTypes;

namespace Fasty.Api.Modules.Monitoring;

public sealed class AnalyticsArchiveMetadataStore
{
    private readonly string _connectionString;

    public AnalyticsArchiveMetadataStore(
        IConfiguration configuration)
    {
        _connectionString =
            configuration.GetConnectionString(
                "FastyDatabase")
            ?? throw new InvalidOperationException(
                "The FastyDatabase connection string is not configured.");
    }

    public async Task RecordExportAsync(
        AnalyticsFinalizedExport export,
        CancellationToken cancellationToken = default)
    {
        await using var connection =
            new NpgsqlConnection(
                _connectionString);

        await connection.OpenAsync(
            cancellationToken);

        await using var command =
            connection.CreateCommand();

        command.CommandText = """
            INSERT INTO analytics.archive_exports
            (
                id,
                range_start_utc,
                range_end_utc,
                row_count,
                file_name,
                sha256,
                exported_at_utc,
                deleted_at_utc,
                status,
                error_message
            )
            VALUES
            (
                @id,
                @range_start_utc,
                @range_end_utc,
                @row_count,
                @file_name,
                @sha256,
                @exported_at_utc,
                NULL,
                'exported',
                NULL
            );
            """;

        command.Parameters.AddWithValue(
            "id",
            export.ExportId);

        command.Parameters.AddWithValue(
            "range_start_utc",
            NpgsqlDbType.TimestampTz,
            export.RangeStartUtc);

        command.Parameters.AddWithValue(
            "range_end_utc",
            NpgsqlDbType.TimestampTz,
            export.RangeEndUtc);

        command.Parameters.AddWithValue(
            "row_count",
            export.RowCount);

        command.Parameters.AddWithValue(
            "file_name",
            export.FileName);

        command.Parameters.AddWithValue(
            "sha256",
            export.Sha256);

        command.Parameters.AddWithValue(
            "exported_at_utc",
            NpgsqlDbType.TimestampTz,
            DateTimeOffset.UtcNow);

        await command.ExecuteNonQueryAsync(
            cancellationToken);
    }
}
