using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Monitoring;

public sealed class InMemoryUserActionStore
    : IUserActionStore
{
    private readonly Lock _sync = new();
    private readonly Queue<UserActionMetric> _actions = new();
    private readonly int _capacity;

    public InMemoryUserActionStore(
        IOptions<MonitoringOptions> optionsAccessor)
    {
        ArgumentNullException.ThrowIfNull(optionsAccessor);

        _capacity = Math.Max(
            100,
            optionsAccessor.Value.ActionCapacity);
    }

    public Task AddAsync(
        UserActionMetric metric,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(metric);
        cancellationToken.ThrowIfCancellationRequested();

        lock (_sync)
        {
            _actions.Enqueue(metric);

            while (_actions.Count > _capacity)
            {
                _actions.Dequeue();
            }
        }

        return Task.CompletedTask;
    }

    public Task<IReadOnlyList<UserActionMetric>>
        GetRecentAsync(
            int limit = 50,
            CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var safeLimit = Math.Clamp(limit, 1, 500);

        lock (_sync)
        {
            IReadOnlyList<UserActionMetric> result =
                _actions
                    .Reverse()
                    .Take(safeLimit)
                    .ToArray();

            return Task.FromResult(result);
        }
    }

    public Task<IReadOnlyList<UserActionMetric>>
        GetRecentForUserAsync(
            string anonymizedUserId,
            int limit = 50,
            CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (string.IsNullOrWhiteSpace(anonymizedUserId))
        {
            return Task.FromResult<
                IReadOnlyList<UserActionMetric>>([]);
        }

        var safeLimit = Math.Clamp(limit, 1, 500);

        lock (_sync)
        {
            IReadOnlyList<UserActionMetric> result =
                _actions
                    .Reverse()
                    .Where(
                        action => string.Equals(
                            action.AnonymizedUserId,
                            anonymizedUserId,
                            StringComparison.Ordinal))
                    .Take(safeLimit)
                    .ToArray();

            return Task.FromResult(result);
        }
    }

    public Task<UserActionSummary> GetSummaryAsync(
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (_sync)
        {
            var actions = _actions.ToArray();

            return Task.FromResult(
                new UserActionSummary(
                    TotalActions: actions.Length,
                    ActiveUsers: actions
                        .Select(
                            action =>
                                action.AnonymizedUserId)
                        .Distinct(StringComparer.Ordinal)
                        .Count(),
                    ActionsByType:
                        CreateActionCounts(actions)));
        }
    }

    public Task<IReadOnlyList<UserDetailSummary>>
        GetUsersAsync(
            CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (_sync)
        {
            IReadOnlyList<UserDetailSummary> result =
                _actions
                    .GroupBy(
                        action =>
                            action.AnonymizedUserId,
                        StringComparer.Ordinal)
                    .Select(CreateUserSummary)
                    .OrderByDescending(
                        user => user.LastActivityUtc)
                    .ToArray();

            return Task.FromResult(result);
        }
    }

    public Task<UserDetailSummary?> GetUserAsync(
        string anonymizedUserId,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (string.IsNullOrWhiteSpace(anonymizedUserId))
        {
            return Task.FromResult<
                UserDetailSummary?>(null);
        }

        lock (_sync)
        {
            var actions = _actions
                .Where(
                    action => string.Equals(
                        action.AnonymizedUserId,
                        anonymizedUserId,
                        StringComparison.Ordinal))
                .ToArray();

            UserDetailSummary? result =
                actions.Length == 0
                    ? null
                    : CreateUserSummary(
                        actions.GroupBy(
                                action =>
                                    action.AnonymizedUserId,
                                StringComparer.Ordinal)
                            .Single());

            return Task.FromResult(result);
        }
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
            FirstActivityUtc: actions[0].TimestampUtc,
            LastActivityUtc: actions[^1].TimestampUtc,
            ActionsByType: CreateActionCounts(actions));
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
