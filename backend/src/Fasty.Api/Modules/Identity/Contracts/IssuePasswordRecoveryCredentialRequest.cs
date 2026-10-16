namespace Fasty.Api.Modules.Identity.Contracts;

public sealed record IssuePasswordRecoveryCredentialRequest(
    string Email);
