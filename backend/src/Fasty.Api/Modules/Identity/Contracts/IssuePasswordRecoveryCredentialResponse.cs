namespace Fasty.Api.Modules.Identity.Contracts;

public sealed record IssuePasswordRecoveryCredentialResponse(
    string RecoveryCredential,
    DateTimeOffset ExpiresAt);
