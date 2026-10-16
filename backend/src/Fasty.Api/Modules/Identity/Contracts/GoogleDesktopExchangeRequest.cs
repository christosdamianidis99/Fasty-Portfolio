namespace Fasty.Api.Modules.Identity.Contracts;

public sealed record GoogleDesktopExchangeRequest(
    string Code,
    string CodeVerifier,
    string RedirectUri);
