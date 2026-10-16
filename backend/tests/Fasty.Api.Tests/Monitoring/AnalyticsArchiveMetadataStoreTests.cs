using Fasty.Api.Modules.Monitoring;
using Microsoft.Extensions.Configuration;
using Npgsql;
using Xunit;

namespace Fasty.Api.Tests.Monitoring;

public sealed class AnalyticsArchiveMetadataStoreTests
{
    [Fact]
    public async Task RecordExportAsync_records_export_without_deleting_actions()
    {
        await using var factory =
            new FastyApiFactory();

        await factory.ResetStorageAsync();

        var actionId =
            Guid.Parse(
                "00000000-0000-0000-0000-000000000020");

        var actionTimestamp =
            new DateTimeOffset(
                2026,
                8,
                1,
                10,
                0,
                0,
                TimeSpan.Zero);

        await InsertActionAsync(
            factory.ConnectionString,
            actionId,
            actionTimestamp);

        var configuration =
            new ConfigurationBuilder()
                .AddInMemoryCollection(
                    new Dictionary<string, string?>
                    {
                        ["ConnectionStrings:FastyDatabase"] =
                            factory.ConnectionString
                    })
                .Build();

        var store =
            new AnalyticsArchiveMetadataStore(
                configuration);

        var exportId =
            Guid.Parse(
                "00000000-0000-0000-0000-000000000030");

        var export =
            new AnalyticsFinalizedExport(
                ExportId: exportId,
                FileName:
                    "analytics-actions-test.csv",
                FilePath:
                    "/tmp/analytics-actions-test.csv",
                Sha256:
                    new string('a', 64),
                RowCount: 1,
                RangeStartUtc:
                    actionTimestamp,
                RangeEndUtc:
                    actionTimestamp,
                CutoffUtc:
                    actionTimestamp.AddDays(1));

        await store.RecordExportAsync(
            export,
            TestContext.Current
                .CancellationToken);

        await using var connection =
            new NpgsqlConnection(
                factory.ConnectionString);

        await connection.OpenAsync(
            TestContext.Current
                .CancellationToken);

        await using var command =
            connection.CreateCommand();

        command.CommandText = """
            SELECT
                id,
                range_start_utc,
                range_end_utc,
                row_count,
                file_name,
                sha256,
                deleted_at_utc,
                status,
                error_message
            FROM analytics.archive_exports
            WHERE id = @id;
            """;

        command.Parameters.AddWithValue(
            "id",
            exportId);

        await using var reader =
            await command.ExecuteReaderAsync(
                TestContext.Current
                    .CancellationToken);

        Assert.True(
            await reader.ReadAsync(
                TestContext.Current
                    .CancellationToken));

        Assert.Equal(
            exportId,
            reader.GetGuid(0));

        Assert.Equal(
            actionTimestamp,
            reader.GetFieldValue<
                DateTimeOffset>(1));

        Assert.Equal(
            actionTimestamp,
            reader.GetFieldValue<
                DateTimeOffset>(2));

        Assert.Equal(
            1,
            reader.GetInt32(3));

        Assert.Equal(
            "analytics-actions-test.csv",
            reader.GetString(4));

        Assert.Equal(
            new string('a', 64),
            reader.GetString(5));

        Assert.True(
            reader.IsDBNull(6));

        Assert.Equal(
            "exported",
            reader.GetString(7));

        Assert.True(
            reader.IsDBNull(8));

        await reader.CloseAsync();

        await using var countCommand =
            connection.CreateCommand();

        countCommand.CommandText = """
            SELECT COUNT(*)::bigint
            FROM analytics.user_actions;
            """;

        Assert.Equal(
            1L,
            (long)(await countCommand.ExecuteScalarAsync(
                TestContext.Current
                    .CancellationToken))!);
    }

    [Fact]
    public async Task RecordExportAsync_duplicate_export_fails_without_touching_actions()
    {
        await using var factory =
            new FastyApiFactory();

        await factory.ResetStorageAsync();

        var actionTimestamp =
            new DateTimeOffset(
                2026,
                8,
                1,
                12,
                0,
                0,
                TimeSpan.Zero);

        await InsertActionAsync(
            factory.ConnectionString,
            Guid.Parse(
                "00000000-0000-0000-0000-000000000021"),
            actionTimestamp);

        var configuration =
            new ConfigurationBuilder()
                .AddInMemoryCollection(
                    new Dictionary<string, string?>
                    {
                        ["ConnectionStrings:FastyDatabase"] =
                            factory.ConnectionString
                    })
                .Build();

        var store =
            new AnalyticsArchiveMetadataStore(
                configuration);

        var export =
            new AnalyticsFinalizedExport(
                ExportId:
                    Guid.Parse(
                        "00000000-0000-0000-0000-000000000031"),
                FileName:
                    "analytics-actions-duplicate.csv",
                FilePath:
                    "/tmp/analytics-actions-duplicate.csv",
                Sha256:
                    new string('b', 64),
                RowCount: 1,
                RangeStartUtc:
                    actionTimestamp,
                RangeEndUtc:
                    actionTimestamp,
                CutoffUtc:
                    actionTimestamp.AddDays(1));

        await store.RecordExportAsync(
            export,
            TestContext.Current.CancellationToken);

        await Assert.ThrowsAsync<PostgresException>(
            async () =>
                await store.RecordExportAsync(
                    export,
                    TestContext.Current.CancellationToken));

        await using var connection =
            new NpgsqlConnection(
                factory.ConnectionString);

        await connection.OpenAsync(
            TestContext.Current.CancellationToken);

        await using var command =
            connection.CreateCommand();

        command.CommandText = """
            SELECT
                (SELECT COUNT(*)::bigint
                 FROM analytics.archive_exports),
                (SELECT COUNT(*)::bigint
                 FROM analytics.user_actions);
            """;

        await using var reader =
            await command.ExecuteReaderAsync(
                TestContext.Current.CancellationToken);

        Assert.True(
            await reader.ReadAsync(
                TestContext.Current.CancellationToken));

        Assert.Equal(
            1L,
            reader.GetInt64(0));

        Assert.Equal(
            1L,
            reader.GetInt64(1));
    }

    private static async Task InsertActionAsync(
        string connectionString,
        Guid id,
        DateTimeOffset timestampUtc)
    {
        await using var connection =
            new NpgsqlConnection(
                connectionString);

        await connection.OpenAsync(
            TestContext.Current
                .CancellationToken);

        await using var command =
            connection.CreateCommand();

        command.CommandText = """
            INSERT INTO analytics.user_actions
            (
                id,
                timestamp_utc,
                anonymized_user_id,
                action_type,
                stored_at_utc
            )
            VALUES
            (
                @id,
                @timestamp_utc,
                'metadata-test-user',
                'metadata-test-action',
                @timestamp_utc
            );
            """;

        command.Parameters.AddWithValue(
            "id",
            id);

        command.Parameters.AddWithValue(
            "timestamp_utc",
            timestampUtc);

        await command.ExecuteNonQueryAsync(
            TestContext.Current
                .CancellationToken);
    }
}
