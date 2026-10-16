namespace Fasty.Api.Modules.Identity.Contracts;

public sealed record RefreshSessionResponse(
    Guid Id,
    string DeviceName,
    DateTimeOffset CreatedAt,
    DateTimeOffset? LastUsedAt,
    DateTimeOffset ExpiresAt);