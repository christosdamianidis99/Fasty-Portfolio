using Fasty.Api.Modules.Identity;
using Xunit;

namespace Fasty.Api.Tests.Identity;

public sealed class RefreshSessionTests
{
    [Fact]
    public void Constructor_CreatesActiveSession()
    {
        var now = DateTimeOffset.UtcNow;

        var session = new RefreshSession(
            Guid.NewGuid(),
            "ABC123",
            "Windows laptop",
            now,
            now.AddDays(30));

        Assert.True(session.IsActive(now));
        Assert.Equal("Windows laptop", session.DeviceName);
        Assert.Null(session.RevokedAt);
    }

    [Fact]
    public void Constructor_TrimsDeviceName()
    {
        var now = DateTimeOffset.UtcNow;

        var session = new RefreshSession(
            Guid.NewGuid(),
            "ABC123",
            "  Android phone  ",
            now,
            now.AddDays(30));

        Assert.Equal("Android phone", session.DeviceName);
    }

    [Fact]
    public void Constructor_RejectsInvalidExpiration()
    {
        var now = DateTimeOffset.UtcNow;

        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new RefreshSession(
                Guid.NewGuid(),
                "ABC123",
                "Test device",
                now,
                now));
    }

    [Fact]
    public void Revoke_MakesSessionInactive()
    {
        var now = DateTimeOffset.UtcNow;

        var session = new RefreshSession(
            Guid.NewGuid(),
            "ABC123",
            "Test device",
            now,
            now.AddDays(30));

        session.Revoke(now.AddMinutes(1));

        Assert.False(session.IsActive(now.AddMinutes(2)));
        Assert.NotNull(session.RevokedAt);
    }

    [Fact]
    public void MarkUsed_UpdatesLastUsedAt()
    {
        var now = DateTimeOffset.UtcNow;

        var session = new RefreshSession(
            Guid.NewGuid(),
            "ABC123",
            "Test device",
            now,
            now.AddDays(30));

        var usedAt = now.AddMinutes(5);

        session.MarkUsed(usedAt);

        Assert.Equal(usedAt, session.LastUsedAt);
    }

    [Fact]
    public void Revoke_StoresReplacementSessionId()
    {
        var now = DateTimeOffset.UtcNow;

        var session = new RefreshSession(
            Guid.NewGuid(),
            "ABC123",
            "Test device",
            now,
            now.AddDays(30));

        var replacementId = Guid.NewGuid();

        session.Revoke(
            now.AddMinutes(1),
            replacementId);

        Assert.Equal(replacementId, session.ReplacedBySessionId);
        Assert.NotNull(session.RevokedAt);
    }

    [Fact]
    public void Revoke_DoesNotOverwriteExistingRevocation()
    {
        var now = DateTimeOffset.UtcNow;

        var session = new RefreshSession(
            Guid.NewGuid(),
            "ABC123",
            "Test device",
            now,
            now.AddDays(30));

        var firstReplacementId = Guid.NewGuid();
        var secondReplacementId = Guid.NewGuid();
        var firstRevocationTime = now.AddMinutes(1);

        session.Revoke(
            firstRevocationTime,
            firstReplacementId);

        session.Revoke(
            now.AddMinutes(2),
            secondReplacementId);

        Assert.Equal(firstRevocationTime, session.RevokedAt);
        Assert.Equal(firstReplacementId, session.ReplacedBySessionId);
    }
}