namespace Fasty.Api.Modules.Identity.Contracts;

public sealed record LoginRequest(
    string Email,
    string Password,
    string DeviceName);