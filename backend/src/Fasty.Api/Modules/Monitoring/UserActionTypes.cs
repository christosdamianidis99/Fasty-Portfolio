namespace Fasty.Api.Modules.Monitoring;

public static class UserActionTypes
{
    public const string NoteCreated = "note_created";
    public const string NoteUpdated = "note_updated";
    public const string NoteDeleted = "note_deleted";
    public const string NotePurged = "note_purged";

    public const string WorkspaceStateChanged =
        "workspace_state_changed";

    public const string UserRegistered = "user_registered";
    public const string UserLoggedIn = "user_logged_in";
    public const string UserLoggedOut = "user_logged_out";
    public const string SessionRevoked = "session_revoked";
}
