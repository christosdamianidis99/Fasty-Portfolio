namespace Fasty.Api.Modules.Identity.Email;

public sealed class DevelopmentAccountEmailSender(
    ILogger<DevelopmentAccountEmailSender> logger)
    : IAccountEmailSender
{
    public bool IsAvailable => true;

    public Task SendVerificationAsync(
        string email,
        string confirmationToken,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        logger.LogInformation(
            "Development email verification for {Email}. Token: {Token}",
            email,
            confirmationToken);

        return Task.CompletedTask;
    }

    public Task SendPasswordResetAsync(
        string email,
        string passwordResetToken,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        logger.LogInformation(
            "Development password reset for {Email}. Token: {Token}",
            email,
            passwordResetToken);

        return Task.CompletedTask;
    }
}
