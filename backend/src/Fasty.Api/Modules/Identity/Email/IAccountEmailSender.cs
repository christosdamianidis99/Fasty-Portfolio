namespace Fasty.Api.Modules.Identity.Email;

public interface IAccountEmailSender
{
    bool IsAvailable { get; }

    Task SendVerificationAsync(
        string email,
        string confirmationToken,
        CancellationToken cancellationToken);

    Task SendPasswordResetAsync(
        string email,
        string passwordResetToken,
        CancellationToken cancellationToken);
}
