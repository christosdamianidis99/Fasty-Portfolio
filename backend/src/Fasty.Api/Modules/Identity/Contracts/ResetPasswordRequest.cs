namespace Fasty.Api.Modules.Identity.Contracts;

public sealed record ResetPasswordRequest(
    string Email,
    string Token,
    string NewPassword);
