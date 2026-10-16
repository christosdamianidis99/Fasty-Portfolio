using System.Net;
using Fasty.Api.Modules.Identity.Email;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;
using MimeKit;
using Xunit;

namespace Fasty.Api.Tests.Identity;

public sealed class SmtpAccountEmailSenderTests
{
    [Fact]
    public async Task Sender_builds_encoded_confirmation_email()
    {
        var transport =
            new CapturingSmtpTransport();

        var sender =
            CreateSender(
                transport);

        await sender.SendVerificationAsync(
            "person+test@example.com",
            "token/value+with=symbols",
            TestContext.Current.CancellationToken);

        var message =
            Assert.IsType<MimeMessage>(
                transport.Message);

        Assert.Equal(
            "Fasty",
            message.From.Mailboxes.Single().Name);

        Assert.Equal(
            "noreply@example.com",
            message.From.Mailboxes.Single().Address);

        Assert.Equal(
            "person+test@example.com",
            message.To.Mailboxes.Single().Address);

        Assert.Equal(
            "Confirm your Fasty email",
            message.Subject);

        var confirmationBody =
            Assert.IsType<MultipartAlternative>(
                message.Body);

        var html =
            Assert.IsType<TextPart>(
                confirmationBody[1])
                .Text;

        const string hrefPrefix =
            "href=\"";

        var hrefStart =
            html.IndexOf(
                hrefPrefix,
                StringComparison.Ordinal);

        Assert.True(
            hrefStart >= 0);

        hrefStart +=
            hrefPrefix.Length;

        var hrefEnd =
            html.IndexOf(
                '"',
                hrefStart);

        Assert.True(
            hrefEnd > hrefStart);

        var confirmationUri =
            new Uri(
                WebUtility.HtmlDecode(
                    html[hrefStart..hrefEnd]));

        Assert.Equal(
            "/confirm-email",
            confirmationUri.AbsolutePath);

        var query =
            QueryHelpers.ParseQuery(
                confirmationUri.Query);

        Assert.Equal(
            "person+test@example.com",
            query["email"].ToString());

        Assert.Equal(
            "token/value+with=symbols",
            query["token"].ToString());

        Assert.Equal(
            "smtp-relay.brevo.com",
            transport.Options?.Host);

        Assert.Equal(
            587,
            transport.Options?.Port);

        Assert.True(
            transport.Options?.UseStartTls);
    }

    [Fact]
    public async Task Sender_builds_password_reset_email()
    {
        var transport =
            new CapturingSmtpTransport();

        var sender =
            CreateSender(
                transport);

        await sender.SendPasswordResetAsync(
            "person@example.com",
            "reset/token+with=symbols",
            TestContext.Current.CancellationToken);

        var message =
            Assert.IsType<MimeMessage>(
                transport.Message);

        Assert.Equal(
            "Reset your Fasty password",
            message.Subject);

        var resetBody =
            Assert.IsType<MultipartAlternative>(
                message.Body);

        var text =
            Assert.IsType<TextPart>(
                resetBody[0])
                .Text;

        Assert.Contains(
            "https://app.example.com/reset-password",
            text,
            StringComparison.Ordinal);

        Assert.Contains(
            "reset%2Ftoken%2Bwith%3Dsymbols",
            text,
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task Disabled_delivery_does_not_call_transport()
    {
        var transport =
            new CapturingSmtpTransport();

        var sender =
            CreateSender(
                transport,
                enabled: false);

        Assert.False(
            sender.IsAvailable);

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => sender.SendVerificationAsync(
                "person@example.com",
                "confirmation-token",
                TestContext.Current.CancellationToken));

        Assert.Null(
            transport.Message);
    }

    [Fact]
    public async Task Resend_provider_does_not_call_smtp_transport()
    {
        var transport =
            new CapturingSmtpTransport();

        var sender =
            CreateSender(
                transport,
                provider:
                    EmailProviderNames.Resend);

        Assert.False(
            sender.IsAvailable);

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => sender.SendVerificationAsync(
                "person@example.com",
                "confirmation-token",
                TestContext.Current.CancellationToken));

        Assert.Null(
            transport.Message);
    }

    private static SmtpAccountEmailSender CreateSender(
        ISmtpEmailTransport transport,
        bool enabled = true,
        string provider =
            EmailProviderNames.Smtp)
    {
        return new SmtpAccountEmailSender(
            transport,
            Options.Create(
                new EmailDeliveryOptions
                {
                    Enabled =
                        enabled,
                    Provider =
                        provider,
                    FromAddress =
                        "noreply@example.com",
                    FromName =
                        "Fasty",
                    ConfirmationUrl =
                        "https://app.example.com/confirm-email",
                    PasswordResetUrl =
                        "https://app.example.com/reset-password"
                }),
            Options.Create(
                new SmtpOptions
                {
                    Host =
                        "smtp-relay.brevo.com",
                    Port =
                        587,
                    Username =
                        "smtp-user",
                    Password =
                        "smtp-password",
                    UseStartTls =
                        true
                }));
    }

    private sealed class CapturingSmtpTransport
        : ISmtpEmailTransport
    {
        public MimeMessage? Message { get; private set; }

        public SmtpOptions? Options { get; private set; }

        public Task SendAsync(
            MimeMessage message,
            SmtpOptions options,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();

            Message =
                message;

            Options =
                options;

            return Task.CompletedTask;
        }
    }
}