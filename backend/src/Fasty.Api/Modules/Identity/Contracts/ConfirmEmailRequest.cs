namespace Fasty.Api.Modules.Identity.Contracts;

public sealed record ConfirmEmailRequest(
    string Email,
    string Token);