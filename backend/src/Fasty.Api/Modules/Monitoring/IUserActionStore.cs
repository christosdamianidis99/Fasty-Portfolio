namespace Fasty.Api.Modules.Monitoring;

public interface IUserActionStore
{
    Task AddAsync(
        UserActionMetric metric,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<UserActionMetric>> GetRecentAsync(
        int limit = 50,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<UserActionMetric>>
        GetRecentForUserAsync(
            string anonymizedUserId,
            int limit = 50,
            CancellationToken cancellationToken = default);

    Task<UserActionSummary> GetSummaryAsync(
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<UserDetailSummary>> GetUsersAsync(
        CancellationToken cancellationToken = default);

    Task<UserDetailSummary?> GetUserAsync(
        string anonymizedUserId,
        CancellationToken cancellationToken = default);
}
