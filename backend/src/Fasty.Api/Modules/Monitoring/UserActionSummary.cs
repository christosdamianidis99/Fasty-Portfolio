namespace Fasty.Api.Modules.Monitoring;

public sealed record UserActionSummary(
    int TotalActions,
    int ActiveUsers,
    IReadOnlyDictionary<string, int> ActionsByType);
