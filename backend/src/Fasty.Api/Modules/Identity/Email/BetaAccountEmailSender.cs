namespace Fasty.Api.Modules.Identity.Email;

public sealed class BetaAccountEmailSender : IAccountEmailSender
{
    public bool IsAvailable => true;

    public Task SendVerificationAsync(
        string email,
        string confirmationToken,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.CompletedTask;
    }

    public Task SendPasswordResetAsync(
        string email,
        string passwordResetToken,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.CompletedTask;
    }
}
