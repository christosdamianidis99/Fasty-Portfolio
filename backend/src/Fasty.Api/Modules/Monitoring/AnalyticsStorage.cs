using Npgsql;

namespace Fasty.Api.Modules.Monitoring;

public static class AnalyticsStorage
{
    public static async Task EnsureStorageAsync(
        IConfiguration configuration,
        CancellationToken cancellationToken = default)
    {
        var connectionString =
            configuration.GetConnectionString(
                "FastyDatabase");

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException(
                "The FastyDatabase connection string is not configured.");
        }

        await using var connection =
            new NpgsqlConnection(connectionString);

        await connection.OpenAsync(cancellationToken);

        await using var command =
            connection.CreateCommand();

        command.CommandText = """
            CREATE SCHEMA IF NOT EXISTS analytics;

            CREATE TABLE IF NOT EXISTS analytics.user_actions
            (
                id uuid PRIMARY KEY,
                timestamp_utc
                    timestamp with time zone
                    NOT NULL,
                anonymized_user_id
                    varchar(32)
                    NOT NULL,
                action_type
                    varchar(100)
                    NOT NULL,
                stored_at_utc
                    timestamp with time zone
                    NOT NULL
                    DEFAULT CURRENT_TIMESTAMP,

                CONSTRAINT uq_user_actions_identity
                    UNIQUE
                    (
                        timestamp_utc,
                        anonymized_user_id,
                        action_type
                    )
            );

            CREATE INDEX IF NOT EXISTS
                ix_user_actions_timestamp
                ON analytics.user_actions
                (
                    timestamp_utc DESC
                );

            CREATE INDEX IF NOT EXISTS
                ix_user_actions_user_timestamp
                ON analytics.user_actions
                (
                    anonymized_user_id,
                    timestamp_utc DESC
                );

            CREATE INDEX IF NOT EXISTS
                ix_user_actions_type_timestamp
                ON analytics.user_actions
                (
                    action_type,
                    timestamp_utc DESC
                );

            CREATE TABLE IF NOT EXISTS analytics.archive_exports
            (
                id uuid PRIMARY KEY,
                range_start_utc
                    timestamp with time zone
                    NOT NULL,
                range_end_utc
                    timestamp with time zone
                    NOT NULL,
                row_count integer NOT NULL,
                file_name text NOT NULL,
                sha256 varchar(64) NOT NULL,
                exported_at_utc
                    timestamp with time zone
                    NOT NULL,
                deleted_at_utc
                    timestamp with time zone,
                status varchar(32) NOT NULL,
                error_message text
            );

            CREATE UNIQUE INDEX IF NOT EXISTS
                ux_archive_exports_file_name
                ON analytics.archive_exports
                (
                    file_name
                );
            """;

        await command.ExecuteNonQueryAsync(
            cancellationToken);
    }
}
