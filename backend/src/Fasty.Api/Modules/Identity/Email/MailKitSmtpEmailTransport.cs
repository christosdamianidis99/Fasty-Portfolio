using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;

namespace Fasty.Api.Modules.Identity.Email;

public sealed class MailKitSmtpEmailTransport
    : ISmtpEmailTransport
{
    public async Task SendAsync(
        MimeMessage message,
        SmtpOptions options,
        CancellationToken cancellationToken)
    {
        using var client =
            new SmtpClient();

        try
        {
            var socketOptions =
                options.UseStartTls
                    ? SecureSocketOptions.StartTls
                    : SecureSocketOptions.Auto;

            await client.ConnectAsync(
                options.Host,
                options.Port,
                socketOptions,
                cancellationToken);

            await client.AuthenticateAsync(
                options.Username,
                options.Password,
                cancellationToken);

            await client.SendAsync(
                message,
                cancellationToken);
        }
        finally
        {
            if (client.IsConnected)
            {
                await client.DisconnectAsync(
                    quit: true,
                    CancellationToken.None);
            }
        }
    }
}