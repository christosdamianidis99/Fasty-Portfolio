using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using Npgsql;
using NpgsqlTypes;

namespace Fasty.Api.Modules.Monitoring;

public sealed class AnalyticsArchiveExporter
{
    private readonly string _connectionString;
    private readonly MonitoringOptions _options;

    public AnalyticsArchiveExporter(
        IConfiguration configuration,
        IOptions<MonitoringOptions> options)
    {
        _connectionString =
            configuration.GetConnectionString(
                "FastyDatabase")
            ?? throw new InvalidOperationException(
                "The FastyDatabase connection string is not configured.");

        _options = options.Value;
    }

    public async Task<AnalyticsTemporaryExport?>
        ExportTemporaryAsync(
            DateTimeOffset cutoffUtc,
            CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(
                _options.ArchiveDirectory))
        {
            throw new InvalidOperationException(
                "The analytics archive directory is not configured.");
        }

        var archiveDirectory =
            Path.GetFullPath(
                _options.ArchiveDirectory);

        Directory.CreateDirectory(
            archiveDirectory);

        var rows =
            await ReadEligibleRowsAsync(
                cutoffUtc,
                cancellationToken);

        if (rows.Count == 0)
        {
            return null;
        }

        var exportId =
            Guid.CreateVersion7();

        var temporaryFileName =
            string.Create(
                CultureInfo.InvariantCulture,
                $"analytics-actions-{exportId:N}.csv.tmp");

        var temporaryFilePath =
            Path.Combine(
                archiveDirectory,
                temporaryFileName);

        try
        {
            await WriteCsvAsync(
                temporaryFilePath,
                rows,
                cancellationToken);

            if (!OperatingSystem.IsWindows())
            {
                File.SetUnixFileMode(
                    temporaryFilePath,
                    UnixFileMode.UserRead |
                    UnixFileMode.UserWrite);
            }
        }
        catch
        {
            File.Delete(temporaryFilePath);
            throw;
        }

        return new AnalyticsTemporaryExport(
            ExportId: exportId,
            TemporaryFileName: temporaryFileName,
            TemporaryFilePath: temporaryFilePath,
            RowCount: rows.Count,
            RangeStartUtc: rows[0].TimestampUtc,
            RangeEndUtc: rows[^1].TimestampUtc,
            CutoffUtc: cutoffUtc);
    }

    public async Task<AnalyticsFinalizedExport>
        FinalizeTemporaryAsync(
            AnalyticsTemporaryExport temporaryExport,
            CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(
                _options.ArchiveDirectory))
        {
            throw new InvalidOperationException(
                "The analytics archive directory is not configured.");
        }

        var archiveDirectory =
            Path.GetFullPath(
                _options.ArchiveDirectory);

        var temporaryPath =
            Path.GetFullPath(
                temporaryExport.TemporaryFilePath);

        if (!string.Equals(
                Path.GetDirectoryName(temporaryPath),
                archiveDirectory,
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "The temporary archive file is outside the configured archive directory.");
        }

        if (!temporaryExport.TemporaryFileName.EndsWith(
                ".csv.tmp",
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "The temporary archive file does not have the expected .csv.tmp suffix.");
        }

        if (!File.Exists(temporaryPath))
        {
            throw new FileNotFoundException(
                "The temporary analytics archive file does not exist.",
                temporaryPath);
        }

        var fileInfo =
            new FileInfo(
                temporaryPath);

        if (fileInfo.Length == 0)
        {
            throw new InvalidOperationException(
                "The temporary analytics archive file is empty.");
        }

        string sha256;

        await using (var stream =
            new FileStream(
                temporaryPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 16_384,
                useAsync: true))
        {
            var hash =
                await SHA256.HashDataAsync(
                    stream,
                    cancellationToken);

            sha256 =
                Convert
                    .ToHexString(hash)
                    .ToLowerInvariant();
        }

        var finalFileName =
            Path.GetFileNameWithoutExtension(
                temporaryExport.TemporaryFileName);

        var finalFilePath =
            Path.Combine(
                archiveDirectory,
                finalFileName);

        File.Move(
            temporaryPath,
            finalFilePath,
            overwrite: false);

        return new AnalyticsFinalizedExport(
            ExportId: temporaryExport.ExportId,
            FileName: finalFileName,
            FilePath: finalFilePath,
            Sha256: sha256,
            RowCount: temporaryExport.RowCount,
            RangeStartUtc: temporaryExport.RangeStartUtc,
            RangeEndUtc: temporaryExport.RangeEndUtc,
            CutoffUtc: temporaryExport.CutoffUtc);
    }

    private async Task<IReadOnlyList<AnalyticsArchiveRow>>
        ReadEligibleRowsAsync(
            DateTimeOffset cutoffUtc,
            CancellationToken cancellationToken)
    {
        await using var connection =
            new NpgsqlConnection(
                _connectionString);

        await connection.OpenAsync(
            cancellationToken);

        await using var command =
            connection.CreateCommand();

        command.CommandText = """
            SELECT
                id,
                timestamp_utc,
                anonymized_user_id,
                action_type,
                stored_at_utc
            FROM analytics.user_actions
            WHERE timestamp_utc < @cutoff_utc
            ORDER BY
                timestamp_utc ASC,
                id ASC;
            """;

        command.Parameters.AddWithValue(
            "cutoff_utc",
            NpgsqlDbType.TimestampTz,
            cutoffUtc);

        await using var reader =
            await command.ExecuteReaderAsync(
                cancellationToken);

        var rows =
            new List<AnalyticsArchiveRow>();

        while (await reader.ReadAsync(
                   cancellationToken))
        {
            rows.Add(
                new AnalyticsArchiveRow(
                    Id: reader.GetGuid(0),
                    TimestampUtc:
                        reader.GetFieldValue<
                            DateTimeOffset>(1),
                    AnonymizedUserId:
                        reader.GetString(2),
                    ActionType:
                        reader.GetString(3),
                    StoredAtUtc:
                        reader.GetFieldValue<
                            DateTimeOffset>(4)));
        }

        return rows;
    }

    private static async Task WriteCsvAsync(
        string path,
        IReadOnlyList<AnalyticsArchiveRow> rows,
        CancellationToken cancellationToken)
    {
        await using var stream =
            new FileStream(
                path,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                bufferSize: 16_384,
                useAsync: true);

        await using var writer =
            new StreamWriter(
                stream,
                new UTF8Encoding(
                    encoderShouldEmitUTF8Identifier: false))
            {
                NewLine = "\n"
            };

        await writer.WriteLineAsync(
            "id,timestamp_utc,anonymized_user_id,action_type,stored_at_utc");

        foreach (var row in rows)
        {
            cancellationToken
                .ThrowIfCancellationRequested();

            var line =
                string.Join(
                    ',',
                    EscapeCsv(
                        row.Id.ToString("D")),
                    EscapeCsv(
                        row.TimestampUtc
                            .ToUniversalTime()
                            .ToString(
                                "O",
                                CultureInfo.InvariantCulture)),
                    EscapeCsv(
                        row.AnonymizedUserId),
                    EscapeCsv(
                        row.ActionType),
                    EscapeCsv(
                        row.StoredAtUtc
                            .ToUniversalTime()
                            .ToString(
                                "O",
                                CultureInfo.InvariantCulture)));

            await writer.WriteLineAsync(line);
        }

        await writer.FlushAsync(
            cancellationToken);
    }

    private static string EscapeCsv(
        string value)
    {
        return string.Concat(
            '"',
            value.Replace(
                "\"",
                "\"\"",
                StringComparison.Ordinal),
            '"');
    }
}

public sealed record AnalyticsFinalizedExport(
    Guid ExportId,
    string FileName,
    string FilePath,
    string Sha256,
    int RowCount,
    DateTimeOffset RangeStartUtc,
    DateTimeOffset RangeEndUtc,
    DateTimeOffset CutoffUtc);

public sealed record AnalyticsTemporaryExport(
    Guid ExportId,
    string TemporaryFileName,
    string TemporaryFilePath,
    int RowCount,
    DateTimeOffset RangeStartUtc,
    DateTimeOffset RangeEndUtc,
    DateTimeOffset CutoffUtc);

internal sealed record AnalyticsArchiveRow(
    Guid Id,
    DateTimeOffset TimestampUtc,
    string AnonymizedUserId,
    string ActionType,
    DateTimeOffset StoredAtUtc);
