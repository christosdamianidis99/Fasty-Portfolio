namespace Fasty.Api.Modules.Identity.Contracts;

public sealed record RedeemPasswordRecoveryCredentialRequest(
    string Email,
    string RecoveryCredential,
    string NewPassword);
