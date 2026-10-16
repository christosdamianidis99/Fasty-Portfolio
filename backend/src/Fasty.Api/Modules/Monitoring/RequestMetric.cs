namespace Fasty.Api.Modules.Monitoring;

public sealed record RequestMetric(
    DateTimeOffset TimestampUtc,
    string Method,
    string Route,
    int StatusCode,
    double DurationMilliseconds,
    string? AnonymizedUserId,
    bool Failed);
