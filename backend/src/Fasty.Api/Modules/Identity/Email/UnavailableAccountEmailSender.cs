namespace Fasty.Api.Modules.Identity.Email;

public sealed class UnavailableAccountEmailSender
    : IAccountEmailSender
{
    public bool IsAvailable => false;

    public Task SendVerificationAsync(
        string email,
        string confirmationToken,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        throw new InvalidOperationException(
            "Email verification delivery is not configured.");
    }

    public Task SendPasswordResetAsync(
        string email,
        string passwordResetToken,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        throw new InvalidOperationException(
            "Password reset delivery is not configured.");
    }
}
