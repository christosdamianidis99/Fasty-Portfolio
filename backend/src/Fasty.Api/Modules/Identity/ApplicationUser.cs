using Microsoft.AspNetCore.Identity;
using Fasty.Api.Modules.Notes;
namespace Fasty.Api.Modules.Identity;

public sealed class ApplicationUser : IdentityUser<Guid>
{
    public DateTimeOffset CreatedAt { get; set; } =
        DateTimeOffset.UtcNow;

    public ICollection<RefreshSession> RefreshSessions { get; private set; } =
        new List<RefreshSession>();

    public ICollection<PasswordRecoveryCredential> PasswordRecoveryCredentials { get; private set; } =
        new List<PasswordRecoveryCredential>();
    public ICollection<Note> Notes { get; private set; } =
new List<Note>();
}