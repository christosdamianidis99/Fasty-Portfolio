namespace Fasty.Api.Modules.Identity;

public sealed class PasswordRecoveryCredential
{
    public Guid Id { get; private set; } = Guid.NewGuid();

    public Guid UserId { get; private set; }

    public string TokenHash { get; private set; } = string.Empty;

    public DateTimeOffset CreatedAt { get; private set; }

    public DateTimeOffset ExpiresAt { get; private set; }

    public DateTimeOffset? ConsumedAt { get; private set; }

    public ApplicationUser User { get; private set; } = null!;

    private PasswordRecoveryCredential()
    {
    }

    public PasswordRecoveryCredential(
        Guid userId,
        string tokenHash,
        DateTimeOffset createdAt,
        DateTimeOffset expiresAt)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(tokenHash);

        if (expiresAt <= createdAt)
        {
            throw new ArgumentOutOfRangeException(
                nameof(expiresAt),
                "The password recovery credential must expire after it is created.");
        }

        UserId = userId;
        TokenHash = tokenHash;
        CreatedAt = createdAt;
        ExpiresAt = expiresAt;
    }

    public bool IsActive(DateTimeOffset utcNow) =>
        ConsumedAt is null && ExpiresAt > utcNow;

    public void Consume(DateTimeOffset utcNow)
    {
        if (ConsumedAt is not null)
        {
            return;
        }

        ConsumedAt = utcNow;
    }
}
