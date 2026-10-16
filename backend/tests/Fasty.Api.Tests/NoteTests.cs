using Fasty.Api.Modules.Notes;
using Xunit;

namespace Fasty.Api.Tests;

public sealed class NoteTests
{
    private static readonly Guid TestUserId =
    Guid.Parse("11111111-1111-1111-1111-111111111111");
    [Fact]
    public void Update_applies_only_when_timestamp_is_newer()
    {
        var createdAt = DateTimeOffset.Parse("2026-07-25T10:00:00Z");
        var note = new Note(
    Guid.NewGuid(),
    TestUserId,
    "Original",
    "Base",
    createdAt);

        var newerApplied = note.Update(
            "Newer",
            "Accepted",
            createdAt.AddMinutes(2));
        var equalApplied = note.Update(
            "Equal",
            "Rejected",
            createdAt.AddMinutes(2));
        var olderApplied = note.Update(
            "Older",
            "Rejected",
            createdAt.AddMinutes(1));

        Assert.True(newerApplied);
        Assert.False(equalApplied);
        Assert.False(olderApplied);
        Assert.Equal("Newer", note.Title);
        Assert.Equal("Accepted", note.Content);
        Assert.Equal(createdAt.AddMinutes(2), note.UpdatedAt);
        Assert.False(note.IsDeleted);
    }

    [Fact]
    public void Delete_creates_a_tombstone_only_when_newer()
    {
        var createdAt = DateTimeOffset.Parse("2026-07-25T11:00:00Z");
        var note = new Note(
            Guid.NewGuid(),
            TestUserId,
            "Note",
            "Content",
            createdAt);

        var staleDelete = note.Delete(createdAt);
        var newerDelete = note.Delete(createdAt.AddMinutes(1));
        var olderDelete = note.Delete(createdAt.AddSeconds(30));

        Assert.False(staleDelete);
        Assert.True(newerDelete);
        Assert.False(olderDelete);
        Assert.True(note.IsDeleted);
        Assert.Equal(createdAt.AddMinutes(1), note.UpdatedAt);
    }

    [Fact]
    public void Stale_update_cannot_resurrect_a_newer_delete()
    {
        var createdAt = DateTimeOffset.Parse("2026-07-25T12:00:00Z");
        var note = new Note(
            Guid.NewGuid(),
            TestUserId,
            "Note",
            "Content",
            createdAt);
        note.Delete(createdAt.AddMinutes(10));

        var applied = note.Update(
            "Stale restoration",
            "Must not apply",
            createdAt.AddMinutes(5));

        Assert.False(applied);
        Assert.True(note.IsDeleted);
        Assert.Equal("Note", note.Title);
    }

    [Fact]
    public void Newer_update_intentionally_restores_a_deleted_note()
    {
        var createdAt = DateTimeOffset.Parse("2026-07-25T13:00:00Z");
        var note = new Note(
            Guid.NewGuid(),
            TestUserId,
            "Note",
            "Content",
            createdAt);
        note.Delete(createdAt.AddMinutes(5));

        var applied = note.Update(
            "Restored",
            "Newer content",
            createdAt.AddMinutes(6));

        Assert.True(applied);
        Assert.False(note.IsDeleted);
        Assert.Equal("Restored", note.Title);
        Assert.Equal("Newer content", note.Content);
    }

    [Fact]
    public void Constructor_requires_a_valid_user_id()
    {
        var createdAt =
            DateTimeOffset.Parse("2026-07-25T14:00:00Z");

        Assert.Throws<ArgumentException>(() =>
            new Note(
                Guid.NewGuid(),
                Guid.Empty,
                "Note",
                "Content",
                createdAt));
    }
}
