namespace Fasty.Api.Modules.Identity.Contracts;

public sealed record LoginResponse(
    string Email,
    string AccessToken,
    DateTimeOffset AccessTokenExpiresAt,
    string RefreshToken,
    DateTimeOffset RefreshTokenExpiresAt,
    Guid RefreshSessionId);