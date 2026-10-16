namespace Fasty.Api.Modules.Identity.Contracts;

public sealed record BootstrapOwnerRequest(
    string? Email,
    string? Password);