namespace Fasty.Api.Modules.Monitoring;

public sealed record UserActionMetric(
    DateTimeOffset TimestampUtc,
    string Action,
    string AnonymizedUserId);
