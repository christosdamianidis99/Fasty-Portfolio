namespace Fasty.Api.Modules.Identity;

public sealed class OwnerBootstrapOptions
{
    public const string SectionName =
        "Authentication:OwnerBootstrap";

    public bool Enabled { get; init; }

    public string Secret { get; init; } =
        string.Empty;
}