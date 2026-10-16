namespace Fasty.Api.Modules.Identity.Contracts;

public sealed record GoogleLoginRequest(
    string IdToken,
    string DeviceName);
