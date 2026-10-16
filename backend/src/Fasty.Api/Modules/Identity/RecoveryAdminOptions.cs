namespace Fasty.Api.Modules.Identity;

public sealed class RecoveryAdminOptions
{
    public const string SectionName =
        "Authentication:RecoveryAdmin";

    public bool Enabled { get; init; }

    public string Secret { get; init; } =
        string.Empty;

    public int CredentialLifetimeMinutes { get; init; } = 30;
}
