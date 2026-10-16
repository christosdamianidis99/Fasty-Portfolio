using System.Text.Encodings.Web;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;
using MimeKit;

namespace Fasty.Api.Modules.Identity.Email;

public sealed class SmtpAccountEmailSender(
    ISmtpEmailTransport transport,
    IOptions<EmailDeliveryOptions> deliveryOptions,
    IOptions<SmtpOptions> smtpOptions)
    : IAccountEmailSender
{
    private readonly EmailDeliveryOptions _deliveryOptions =
        deliveryOptions.Value;

    private readonly SmtpOptions _smtpOptions =
        smtpOptions.Value;

    public bool IsAvailable =>
        _deliveryOptions.Enabled
        && string.Equals(
            _deliveryOptions.Provider,
            EmailProviderNames.Smtp,
            StringComparison.OrdinalIgnoreCase);

    public Task SendVerificationAsync(
        string email,
        string confirmationToken,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!IsAvailable)
        {
            throw new InvalidOperationException(
                "SMTP email delivery is not configured.");
        }

        var confirmationUrl =
            QueryHelpers.AddQueryString(
                _deliveryOptions.ConfirmationUrl,
                new Dictionary<string, string?>
                {
                    ["email"] = email,
                    ["token"] = confirmationToken
                });

        var message =
            CreateMessage(
                email,
                "Confirm your Fasty email",
                """
                Confirm your email address to activate your Fasty account.
                """,
                "Confirm your email",
                confirmationUrl,
                """
                If you did not create this account, you can ignore this message.
                """);

        return transport.SendAsync(
            message,
            _smtpOptions,
            cancellationToken);
    }

    public Task SendPasswordResetAsync(
        string email,
        string passwordResetToken,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!IsAvailable)
        {
            throw new InvalidOperationException(
                "SMTP email delivery is not configured.");
        }

        var passwordResetUrl =
            QueryHelpers.AddQueryString(
                _deliveryOptions.PasswordResetUrl,
                new Dictionary<string, string?>
                {
                    ["email"] = email,
                    ["token"] = passwordResetToken
                });

        var message =
            CreateMessage(
                email,
                "Reset your Fasty password",
                """
                A password reset was requested for your Fasty account.
                """,
                "Reset your password",
                passwordResetUrl,
                """
                If you did not request this, you can ignore this message.
                """);

        return transport.SendAsync(
            message,
            _smtpOptions,
            cancellationToken);
    }

    private MimeMessage CreateMessage(
        string recipient,
        string subject,
        string introduction,
        string actionText,
        string actionUrl,
        string closing)
    {
        var message =
            new MimeMessage();

        message.From.Add(
            new MailboxAddress(
                _deliveryOptions.FromName,
                _deliveryOptions.FromAddress));

        message.To.Add(
            MailboxAddress.Parse(
                recipient));

        message.Subject =
            subject;

        var encodedUrl =
            HtmlEncoder.Default.Encode(
                actionUrl);

        var bodyBuilder =
            new BodyBuilder
            {
                TextBody =
                    $"""
                    {introduction}

                    {actionText}:
                    {actionUrl}

                    {closing}
                    """,
                HtmlBody =
                    $"""
                    <p>{introduction}</p>
                    <p>
                      <a href="{encodedUrl}">
                        {actionText}
                      </a>
                    </p>
                    <p>{closing}</p>
                    """
            };

        message.Body =
            bodyBuilder.ToMessageBody();

        return message;
    }
}