namespace Fasty.Api.Modules.Identity.Contracts;

public sealed record RegisterRequest(
    string Email,
    string Password);