using MimeKit;

namespace Fasty.Api.Modules.Identity.Email;

public interface ISmtpEmailTransport
{
    Task SendAsync(
        MimeMessage message,
        SmtpOptions options,
        CancellationToken cancellationToken);
}