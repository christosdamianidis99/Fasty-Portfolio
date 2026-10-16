namespace Fasty.Api.Modules.Identity;

public sealed class RegistrationOptions
{
    public const string SectionName =
        "Authentication:Registration";

    public bool Enabled { get; init; }

    public bool RequireEmailVerification { get; init; } = true;
}
