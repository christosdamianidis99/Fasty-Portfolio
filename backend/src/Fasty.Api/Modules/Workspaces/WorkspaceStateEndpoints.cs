using System.Security.Claims;
using Fasty.Api.Modules.Monitoring;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;

namespace Fasty.Api.Modules.Workspaces;

public static class WorkspaceStateEndpoints
{
    private const string TableName =
        "notes.workspace_state";

    public static IEndpointRouteBuilder MapWorkspaceStateEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints
            .MapGroup("/api/v1/workspace-state")
            .WithTags("Workspaces")
            .RequireAuthorization();

        group.MapGet("/", async (
            ClaimsPrincipal principal,
            IConfiguration configuration,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetUserId(
                    principal,
                    out var userId))
            {
                return Results.Unauthorized();
            }

            await using var connection =
                CreateConnection(configuration);

            await connection.OpenAsync(
                cancellationToken);

            var state =
                await ReadCurrentStateAsync(
                    connection,
                    userId,
                    cancellationToken);

            return state is null
                ? Results.NoContent()
                : Results.Ok(state.Value);
        });

        group.MapPut("/", async (
            JsonElement state,
            ClaimsPrincipal principal,
            IConfiguration configuration,
            IUserActionTracker actionTracker,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetUserId(
                    principal,
                    out var userId))
            {
                return Results.Unauthorized();
            }

            if (state.ValueKind
                != JsonValueKind.Object)
            {
                return Results.ValidationProblem(
                    new Dictionary<string, string[]>
                    {
                        ["state"] =
                        [
                            "Workspace state must be a JSON object."
                        ]
                    });
            }

            if (!state.TryGetProperty(
                    "updatedAt",
                    out var updatedAtProperty)
                || updatedAtProperty.ValueKind
                    != JsonValueKind.String
                || !DateTimeOffset.TryParse(
                    updatedAtProperty.GetString(),
                    out var updatedAt))
            {
                return Results.ValidationProblem(
                    new Dictionary<string, string[]>
                    {
                        ["updatedAt"] =
                        [
                            "A valid UTC updatedAt value is required."
                        ]
                    });
            }

            var stateJson =
                state.GetRawText();

            await using var connection =
                CreateConnection(configuration);

            await connection.OpenAsync(
                cancellationToken);

            await using (var command =
                connection.CreateCommand())
            {
                command.CommandText = $"""
                    INSERT INTO {TableName}
                    (
                        user_id,
                        state_json,
                        updated_at
                    )
                    VALUES
                    (
                        @user_id,
                        @state_json,
                        @updated_at
                    )
                    ON CONFLICT (user_id)
                    DO UPDATE SET
                        state_json =
                            EXCLUDED.state_json,
                        updated_at =
                            EXCLUDED.updated_at
                    WHERE
                        {TableName}.updated_at
                        < EXCLUDED.updated_at;
                    """;

                command.Parameters.AddWithValue(
                    "user_id",
                    NpgsqlDbType.Uuid,
                    userId);

                command.Parameters.AddWithValue(
                    "state_json",
                    NpgsqlDbType.Jsonb,
                    stateJson);

                command.Parameters.AddWithValue(
                    "updated_at",
                    updatedAt);

                await command.ExecuteNonQueryAsync(
                    cancellationToken);
            }

            var storedState =
                await ReadCurrentStateAsync(
                    connection,
                    userId,
                    cancellationToken);

            if (storedState is null)
            {
                return Results.Problem(
                    "Workspace state could not be stored.",
                    statusCode: 500);
            }

            await actionTracker.TrackAsync(
                userId,
                UserActionTypes.WorkspaceStateChanged);

            return Results.Ok(storedState.Value);
        });

        return endpoints;
    }

    public static async Task EnsureStorageAsync(
        IConfiguration configuration,
        CancellationToken cancellationToken = default)
    {
        await using var connection =
            CreateConnection(configuration);

        await connection.OpenAsync(
            cancellationToken);

        await using var command =
            connection.CreateCommand();

        command.CommandText = $"""
    CREATE TABLE IF NOT EXISTS {TableName}
    (
        user_id uuid NOT NULL,
        state_json jsonb NOT NULL,
        updated_at
            timestamp with time zone
            NOT NULL
    );

    ALTER TABLE {TableName}
        ADD COLUMN IF NOT EXISTS
            user_id uuid;

    ALTER TABLE {TableName}
        DROP CONSTRAINT IF EXISTS
            workspace_state_id_check;

    ALTER TABLE {TableName}
        DROP CONSTRAINT IF EXISTS
            workspace_state_pkey;

    ALTER TABLE {TableName}
        ALTER COLUMN user_id SET NOT NULL;

    ALTER TABLE {TableName}
        DROP COLUMN IF EXISTS id;

    DO $$
    BEGIN
        IF NOT EXISTS
        (
            SELECT 1
            FROM pg_constraint
            WHERE conname =
                'workspace_state_user_id_key'
              AND conrelid =
                '{TableName}'::regclass
        )
        THEN
            ALTER TABLE {TableName}
                ADD CONSTRAINT
                    workspace_state_user_id_key
                UNIQUE (user_id);
        END IF;
    END
    $$;

    DO $$
    BEGIN
        IF NOT EXISTS
        (
            SELECT 1
            FROM pg_constraint
            WHERE conname =
                'workspace_state_user_id_fkey'
              AND conrelid =
                '{TableName}'::regclass
        )
        THEN
            ALTER TABLE {TableName}
                ADD CONSTRAINT
                    workspace_state_user_id_fkey
                FOREIGN KEY (user_id)
                REFERENCES auth.users ("Id")
                ON DELETE CASCADE;
        END IF;
    END
    $$;

    CREATE INDEX IF NOT EXISTS
        ix_workspace_state_updated_at
        ON {TableName} (updated_at);
    """;

        await command.ExecuteNonQueryAsync(
            cancellationToken);
    }

    private static NpgsqlConnection CreateConnection(
        IConfiguration configuration)
    {
        var connectionString =
            configuration.GetConnectionString(
                "FastyDatabase");

        if (string.IsNullOrWhiteSpace(
                connectionString))
        {
            throw new InvalidOperationException(
                "The FastyDatabase connection string is not configured.");
        }

        return new NpgsqlConnection(
            connectionString);
    }

    private static async Task<JsonElement?>
        ReadCurrentStateAsync(
            NpgsqlConnection connection,
            Guid userId,
            CancellationToken cancellationToken)
    {
        await using var command =
            connection.CreateCommand();

        command.CommandText = $"""
            SELECT state_json::text
            FROM {TableName}
            WHERE user_id = @user_id;
            """;

        command.Parameters.AddWithValue(
            "user_id",
            NpgsqlDbType.Uuid,
            userId);

        var value =
            await command.ExecuteScalarAsync(
                cancellationToken);

        if (value is not string json
            || string.IsNullOrWhiteSpace(json))
        {
            return null;
        }

        return JsonSerializer
            .Deserialize<JsonElement>(json);
    }

    private static bool TryGetUserId(
        ClaimsPrincipal principal,
        out Guid userId)
    {
        var userIdValue =
            principal.FindFirstValue(
                ClaimTypes.NameIdentifier);

        return Guid.TryParse(
                userIdValue,
                out userId)
            && userId != Guid.Empty;
    }
}