using Fasty.Api.Modules.Identity;
namespace Fasty.Api.Modules.Notes;

public sealed class Note
{
    public const string PurgedTitle = "__FASTY_PURGED__";

    private Note()
    {
    }

    public Note(
        Guid id,
        Guid userId,
        string title,
        string content,
        DateTimeOffset createdAt)
    {
        if (userId == Guid.Empty)
        {
            throw new ArgumentException(
                "A valid user ID is required.",
                nameof(userId));
        }

        Id = id;
        UserId = userId;
        CreatedAt = createdAt;
        UpdatedAt = createdAt;
        IsDeleted = false;

        SetContent(title, content);
    }

    public Guid Id { get; private set; }
    public Guid UserId { get; private set; }

    public ApplicationUser User { get; private set; } = null!;

    public string Title { get; private set; } = string.Empty;

    public string Content { get; private set; } = string.Empty;

    public DateTimeOffset CreatedAt { get; private set; }

    public DateTimeOffset UpdatedAt { get; private set; }

    public bool IsDeleted { get; private set; }

    public bool IsPurged => IsDeleted && Title == PurgedTitle;

    public bool Update(
        string title,
        string content,
        DateTimeOffset updatedAt)
    {
        if (IsPurged || updatedAt <= UpdatedAt)
        {
            return false;
        }

        SetContent(title, content);
        UpdatedAt = updatedAt;
        IsDeleted = false;

        return true;
    }

    public bool Delete(DateTimeOffset deletedAt)
    {
        if (IsPurged || deletedAt <= UpdatedAt)
        {
            return false;
        }

        UpdatedAt = deletedAt;
        IsDeleted = true;

        return true;
    }

    public bool Purge(DateTimeOffset purgedAt)
    {
        if (IsPurged || purgedAt <= UpdatedAt)
        {
            return false;
        }

        Title = PurgedTitle;
        Content = string.Empty;
        UpdatedAt = purgedAt;
        IsDeleted = true;
        return true;
    }

    private void SetContent(string title, string content)
    {
        Title = title.Trim();
        Content = content;
    }
}
