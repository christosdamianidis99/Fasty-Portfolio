using Fasty.Api.Modules.Monitoring;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Npgsql;
using Xunit;

namespace Fasty.Api.Tests.Monitoring;

public sealed class AnalyticsArchiveExporterTests
{
    [Fact]
    public async Task ExportTemporaryAsync_writes_ordered_escaped_csv()
    {
        await using var factory =
            new FastyApiFactory();

        await factory.ResetStorageAsync();

        var archiveDirectory =
            Path.Combine(
                Path.GetTempPath(),
                $"fasty-archive-test-{Guid.NewGuid():N}");

        Directory.CreateDirectory(
            archiveDirectory);

        try
        {
            var olderTimestamp =
                new DateTimeOffset(
                    2026,
                    8,
                    1,
                    10,
                    0,
                    0,
                    TimeSpan.Zero);

            var newerTimestamp =
                olderTimestamp.AddHours(1);

            await InsertActionAsync(
                factory.ConnectionString,
                Guid.Parse(
                    "00000000-0000-0000-0000-000000000002"),
                newerTimestamp,
                "user-b",
                "action,\"quoted\"",
                newerTimestamp.AddMinutes(1));

            await InsertActionAsync(
                factory.ConnectionString,
                Guid.Parse(
                    "00000000-0000-0000-0000-000000000001"),
                olderTimestamp,
                "user-a",
                "line-one\nline-two",
                olderTimestamp.AddMinutes(1));

            var configuration =
                new ConfigurationBuilder()
                    .AddInMemoryCollection(
                        new Dictionary<string, string?>
                        {
                            ["ConnectionStrings:FastyDatabase"] =
                                factory.ConnectionString
                        })
                    .Build();

            var exporter =
                new AnalyticsArchiveExporter(
                    configuration,
                    Options.Create(
                        new MonitoringOptions
                        {
                            ArchiveDirectory =
                                archiveDirectory
                        }));

            var result =
                await exporter.ExportTemporaryAsync(
                    newerTimestamp.AddMinutes(1),
                    TestContext.Current
                        .CancellationToken);

            Assert.NotNull(result);
            Assert.Equal(2, result.RowCount);
            Assert.Equal(
                olderTimestamp,
                result.RangeStartUtc);
            Assert.Equal(
                newerTimestamp,
                result.RangeEndUtc);
            Assert.EndsWith(
                ".csv.tmp",
                result.TemporaryFileName,
                StringComparison.Ordinal);
            Assert.True(
                File.Exists(
                    result.TemporaryFilePath));

            var csv =
                await File.ReadAllTextAsync(
                    result.TemporaryFilePath,
                    TestContext.Current
                        .CancellationToken);

            Assert.StartsWith(
                "id,timestamp_utc,anonymized_user_id,action_type,stored_at_utc\n",
                csv,
                StringComparison.Ordinal);

            var olderPosition =
                csv.IndexOf(
                    "\"00000000-0000-0000-0000-000000000001\"",
                    StringComparison.Ordinal);

            var newerPosition =
                csv.IndexOf(
                    "\"00000000-0000-0000-0000-000000000002\"",
                    StringComparison.Ordinal);

            Assert.True(
                olderPosition >= 0);
            Assert.True(
                newerPosition > olderPosition);

            Assert.Contains(
                "\"action,\"\"quoted\"\"\"",
                csv,
                StringComparison.Ordinal);

            Assert.Contains(
                "\"line-one\nline-two\"",
                csv,
                StringComparison.Ordinal);

            Assert.Equal(
                2,
                await CountActionsAsync(
                    factory.ConnectionString));
        }
        finally
        {
            Directory.Delete(
                archiveDirectory,
                recursive: true);
        }
    }

    [Fact]
    public async Task FinalizeTemporaryAsync_hashes_and_atomically_renames_file()
    {
        await using var factory =
            new FastyApiFactory();

        await factory.ResetStorageAsync();

        var archiveDirectory =
            Path.Combine(
                Path.GetTempPath(),
                $"fasty-archive-test-{Guid.NewGuid():N}");

        Directory.CreateDirectory(
            archiveDirectory);

        try
        {
            var timestamp =
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
                Guid.Parse(
                    "00000000-0000-0000-0000-000000000010"),
                timestamp,
                "user-finalize",
                "archive-finalize",
                timestamp.AddMinutes(1));

            var configuration =
                new ConfigurationBuilder()
                    .AddInMemoryCollection(
                        new Dictionary<string, string?>
                        {
                            ["ConnectionStrings:FastyDatabase"] =
                                factory.ConnectionString
                        })
                    .Build();

            var exporter =
                new AnalyticsArchiveExporter(
                    configuration,
                    Options.Create(
                        new MonitoringOptions
                        {
                            ArchiveDirectory =
                                archiveDirectory
                        }));

            var temporary =
                await exporter.ExportTemporaryAsync(
                    timestamp.AddMinutes(1),
                    TestContext.Current
                        .CancellationToken);

            Assert.NotNull(temporary);
            Assert.True(
                File.Exists(
                    temporary.TemporaryFilePath));

            var expectedHash =
                Convert.ToHexString(
                    System.Security.Cryptography.SHA256.HashData(
                        await File.ReadAllBytesAsync(
                            temporary.TemporaryFilePath,
                            TestContext.Current
                                .CancellationToken)))
                    .ToLowerInvariant();

            var finalized =
                await exporter.FinalizeTemporaryAsync(
                    temporary,
                    TestContext.Current
                        .CancellationToken);

            Assert.Equal(
                temporary.ExportId,
                finalized.ExportId);
            Assert.Equal(
                temporary.RowCount,
                finalized.RowCount);
            Assert.Equal(
                expectedHash,
                finalized.Sha256);

            Assert.Equal(
                64,
                finalized.Sha256.Length);

            Assert.EndsWith(
                ".csv",
                finalized.FileName,
                StringComparison.Ordinal);

            Assert.False(
                finalized.FileName.EndsWith(
                    ".tmp",
                    StringComparison.Ordinal));

            Assert.False(
                File.Exists(
                    temporary.TemporaryFilePath));

            Assert.True(
                File.Exists(
                    finalized.FilePath));

            Assert.Equal(
                1,
                await CountActionsAsync(
                    factory.ConnectionString));
        }
        finally
        {
            Directory.Delete(
                archiveDirectory,
                recursive: true);
        }
    }

    [Fact]
    public async Task ExportTemporaryAsync_returns_null_for_no_rows()
    {
        await using var factory =
            new FastyApiFactory();

        await factory.ResetStorageAsync();

        var archiveDirectory =
            Path.Combine(
                Path.GetTempPath(),
                $"fasty-archive-test-{Guid.NewGuid():N}");

        Directory.CreateDirectory(
            archiveDirectory);

        try
        {
            var configuration =
                new ConfigurationBuilder()
                    .AddInMemoryCollection(
                        new Dictionary<string, string?>
                        {
                            ["ConnectionStrings:FastyDatabase"] =
                                factory.ConnectionString
                        })
                    .Build();

            var exporter =
                new AnalyticsArchiveExporter(
                    configuration,
                    Options.Create(
                        new MonitoringOptions
                        {
                            ArchiveDirectory =
                                archiveDirectory
                        }));

            var result =
                await exporter.ExportTemporaryAsync(
                    DateTimeOffset.UtcNow,
                    TestContext.Current
                        .CancellationToken);

            Assert.Null(result);
            Assert.Empty(
                Directory.GetFiles(
                    archiveDirectory));
        }
        finally
        {
            Directory.Delete(
                archiveDirectory,
                recursive: true);
        }
    }

    private static async Task InsertActionAsync(
        string connectionString,
        Guid id,
        DateTimeOffset timestampUtc,
        string anonymizedUserId,
        string actionType,
        DateTimeOffset storedAtUtc)
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
                @anonymized_user_id,
                @action_type,
                @stored_at_utc
            );
            """;

        command.Parameters.AddWithValue(
            "id",
            id);
        command.Parameters.AddWithValue(
            "timestamp_utc",
            timestampUtc);
        command.Parameters.AddWithValue(
            "anonymized_user_id",
            anonymizedUserId);
        command.Parameters.AddWithValue(
            "action_type",
            actionType);
        command.Parameters.AddWithValue(
            "stored_at_utc",
            storedAtUtc);

        await command.ExecuteNonQueryAsync(
            TestContext.Current
                .CancellationToken);
    }

    private static async Task<long> CountActionsAsync(
        string connectionString)
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
            SELECT COUNT(*)::bigint
            FROM analytics.user_actions;
            """;

        return (long)(await command.ExecuteScalarAsync(
            TestContext.Current
                .CancellationToken))!;
    }
}
