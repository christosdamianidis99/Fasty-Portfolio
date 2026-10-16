namespace Fasty.Api.Modules.Monitoring;

public sealed record UserDetailSummary(
    string AnonymizedUserId,
    int TotalActions,
    DateTimeOffset FirstActivityUtc,
    DateTimeOffset LastActivityUtc,
    IReadOnlyDictionary<string, int> ActionsByType);
