namespace Fasty.Api.Modules.Identity.Google;

public sealed record GoogleIdentity(
    string Subject,
    string Email,
    bool EmailVerified,
    string? HostedDomain);
