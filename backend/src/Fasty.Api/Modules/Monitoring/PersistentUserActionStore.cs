using Npgsql;
using NpgsqlTypes;

namespace Fasty.Api.Modules.Monitoring;

public sealed class PersistentUserActionStore
    : IUserActionStore
{
    private readonly string _connectionString;

    public PersistentUserActionStore(
        IConfiguration configuration)
    {
        _connectionString =
            configuration.GetConnectionString(
                "FastyDatabase")
            ?? throw new InvalidOperationException(
                "The FastyDatabase connection string is not configured.");
    }

    public async Task AddAsync(
        UserActionMetric metric,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(metric);

        await using var connection =
            await OpenConnectionAsync(cancellationToken);

        await using var command =
            connection.CreateCommand();

        command.CommandText = """
            INSERT INTO analytics.user_actions
            (
                id,
                timestamp_utc,
                anonymized_user_id,
                action_type
            )
            VALUES
            (
                @id,
                @timestamp_utc,
                @anonymized_user_id,
                @action_type
            )
            ON CONFLICT
            (
                timestamp_utc,
                anonymized_user_id,
                action_type
            )
            DO NOTHING;
            """;

        command.Parameters.AddWithValue(
            "id",
            NpgsqlDbType.Uuid,
            Guid.CreateVersion7());

        command.Parameters.AddWithValue(
            "timestamp_utc",
            NpgsqlDbType.TimestampTz,
            metric.TimestampUtc);

        command.Parameters.AddWithValue(
            "anonymized_user_id",
            NpgsqlDbType.Varchar,
            metric.AnonymizedUserId);

        command.Parameters.AddWithValue(
            "action_type",
            NpgsqlDbType.Varchar,
            metric.Action);

        await command.ExecuteNonQueryAsync(
            cancellationToken);
    }

    public Task<IReadOnlyList<UserActionMetric>>
        GetRecentAsync(
            int limit = 50,
            CancellationToken cancellationToken = default)
    {
        return ReadActionsAsync(
            """
            SELECT
                timestamp_utc,
                action_type,
                anonymized_user_id
            FROM analytics.user_actions
            ORDER BY timestamp_utc DESC
            LIMIT @limit;
            """,
            command => command.Parameters.AddWithValue(
                "limit",
                NpgsqlDbType.Integer,
                Math.Clamp(limit, 1, 500)),
            cancellationToken);
    }

    public Task<IReadOnlyList<UserActionMetric>>
        GetRecentForUserAsync(
            string anonymizedUserId,
            int limit = 50,
            CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(anonymizedUserId))
        {
            return Task.FromResult<
                IReadOnlyList<UserActionMetric>>([]);
        }

        return ReadActionsAsync(
            """
            SELECT
                timestamp_utc,
                action_type,
                anonymized_user_id
            FROM analytics.user_actions
            WHERE anonymized_user_id =
                @anonymized_user_id
            ORDER BY timestamp_utc DESC
            LIMIT @limit;
            """,
            command =>
            {
                command.Parameters.AddWithValue(
                    "anonymized_user_id",
                    NpgsqlDbType.Varchar,
                    anonymizedUserId);

                command.Parameters.AddWithValue(
                    "limit",
                    NpgsqlDbType.Integer,
                    Math.Clamp(limit, 1, 500));
            },
            cancellationToken);
    }

    public async Task<UserActionSummary> GetSummaryAsync(
        CancellationToken cancellationToken = default)
    {
        var actions =
            await ReadAllActionsAsync(
                cancellationToken);

        return new UserActionSummary(
            TotalActions: actions.Count,
            ActiveUsers: actions
                .Select(
                    action =>
                        action.AnonymizedUserId)
                .Distinct(StringComparer.Ordinal)
                .Count(),
            ActionsByType:
                CreateActionCounts(actions));
    }

    public async Task<IReadOnlyList<UserDetailSummary>>
        GetUsersAsync(
            CancellationToken cancellationToken = default)
    {
        var actions =
            await ReadAllActionsAsync(
                cancellationToken);

        return actions
            .GroupBy(
                action => action.AnonymizedUserId,
                StringComparer.Ordinal)
            .Select(CreateUserSummary)
            .OrderByDescending(
                user => user.LastActivityUtc)
            .ToArray();
    }

    public async Task<UserDetailSummary?> GetUserAsync(
        string anonymizedUserId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(anonymizedUserId))
        {
            return null;
        }

        var actions = await ReadActionsAsync(
            """
            SELECT
                timestamp_utc,
                action_type,
                anonymized_user_id
            FROM analytics.user_actions
            WHERE anonymized_user_id =
                @anonymized_user_id
            ORDER BY timestamp_utc ASC;
            """,
            command => command.Parameters.AddWithValue(
                "anonymized_user_id",
                NpgsqlDbType.Varchar,
                anonymizedUserId),
            cancellationToken);

        if (actions.Count == 0)
        {
            return null;
        }

        return CreateUserSummary(
            actions.GroupBy(
                    action =>
                        action.AnonymizedUserId,
                    StringComparer.Ordinal)
                .Single());
    }

    private Task<IReadOnlyList<UserActionMetric>>
        ReadAllActionsAsync(
            CancellationToken cancellationToken)
    {
        return ReadActionsAsync(
            """
            SELECT
                timestamp_utc,
                action_type,
                anonymized_user_id
            FROM analytics.user_actions
            ORDER BY timestamp_utc ASC;
            """,
            configureCommand: null,
            cancellationToken);
    }

    private async Task<IReadOnlyList<UserActionMetric>>
        ReadActionsAsync(
            string sql,
            Action<NpgsqlCommand>? configureCommand,
            CancellationToken cancellationToken)
    {
        await using var connection =
            await OpenConnectionAsync(cancellationToken);

        await using var command =
            connection.CreateCommand();

        command.CommandText = sql;
        configureCommand?.Invoke(command);

        await using var reader =
            await command.ExecuteReaderAsync(
                cancellationToken);

        var actions =
            new List<UserActionMetric>();

        while (await reader.ReadAsync(
                   cancellationToken))
        {
            actions.Add(
                new UserActionMetric(
                    TimestampUtc:
                        reader.GetFieldValue<
                            DateTimeOffset>(0),
                    Action: reader.GetString(1),
                    AnonymizedUserId:
                        reader.GetString(2)));
        }

        return actions;
    }

    private async Task<NpgsqlConnection>
        OpenConnectionAsync(
            CancellationToken cancellationToken)
    {
        var connection =
            new NpgsqlConnection(
                _connectionString);

        await connection.OpenAsync(
            cancellationToken);

        return connection;
    }

    private static UserDetailSummary CreateUserSummary(
        IGrouping<string, UserActionMetric> group)
    {
        var actions = group
            .OrderBy(action => action.TimestampUtc)
            .ToArray();

        return new UserDetailSummary(
            AnonymizedUserId: group.Key,
            TotalActions: actions.Length,
            FirstActivityUtc:
                actions[0].TimestampUtc,
            LastActivityUtc:
                actions[^1].TimestampUtc,
            ActionsByType:
                CreateActionCounts(actions));
    }

    private static IReadOnlyDictionary<string, int>
        CreateActionCounts(
            IEnumerable<UserActionMetric> actions)
    {
        return actions
            .GroupBy(
                action => action.Action,
                StringComparer.Ordinal)
            .OrderByDescending(group => group.Count())
            .ThenBy(
                group => group.Key,
                StringComparer.Ordinal)
            .ToDictionary(
                group => group.Key,
                group => group.Count(),
                StringComparer.Ordinal);
    }
}
