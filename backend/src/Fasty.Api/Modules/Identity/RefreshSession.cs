namespace Fasty.Api.Modules.Identity;

public sealed class RefreshSession
{
    public Guid Id { get; private set; } = Guid.NewGuid();

    public Guid UserId { get; private set; }

    public string TokenHash { get; private set; } = string.Empty;

    public string DeviceName { get; private set; } = string.Empty;

    public DateTimeOffset CreatedAt { get; private set; }

    public DateTimeOffset ExpiresAt { get; private set; }

    public DateTimeOffset? LastUsedAt { get; private set; }

    public DateTimeOffset? RevokedAt { get; private set; }

    public Guid? ReplacedBySessionId { get; private set; }

    public ApplicationUser User { get; private set; } = null!;

    private RefreshSession()
    {
    }

    public RefreshSession(
        Guid userId,
        string tokenHash,
        string deviceName,
        DateTimeOffset createdAt,
        DateTimeOffset expiresAt)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(tokenHash);
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceName);

        if (expiresAt <= createdAt)
        {
            throw new ArgumentOutOfRangeException(
                nameof(expiresAt),
                "The refresh session must expire after it is created.");
        }

        UserId = userId;
        TokenHash = tokenHash;
        DeviceName = deviceName.Trim();
        CreatedAt = createdAt;
        ExpiresAt = expiresAt;
    }

    public bool IsActive(DateTimeOffset utcNow) =>
        RevokedAt is null && ExpiresAt > utcNow;

    public void MarkUsed(DateTimeOffset utcNow)
    {
        LastUsedAt = utcNow;
    }

    public void Revoke(
        DateTimeOffset utcNow,
        Guid? replacedBySessionId = null)
    {
        if (RevokedAt is not null)
        {
            return;
        }

        RevokedAt = utcNow;
        ReplacedBySessionId = replacedBySessionId;
    }
}