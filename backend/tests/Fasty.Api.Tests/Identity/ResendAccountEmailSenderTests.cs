using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Fasty.Api.Modules.Identity.Email;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;
using Xunit;

namespace Fasty.Api.Tests.Identity;

public sealed class ResendAccountEmailSenderTests
{
    [Fact]
    public async Task Sender_posts_encoded_confirmation_email()
    {
        var handler =
            new CapturingHttpMessageHandler();

        using var client =
            new HttpClient(handler)
            {
                BaseAddress =
                    new Uri(
                        "https://api.resend.com/")
            };

        var sender =
            CreateSender(
                client);

        await sender.SendVerificationAsync(
            "person+test@example.com",
            "token/value+with=symbols",
            TestContext.Current.CancellationToken);

        var request =
            Assert.IsType<HttpRequestMessage>(
                handler.Request);

        Assert.Equal(
            HttpMethod.Post,
            request.Method);

        Assert.Equal(
            "https://api.resend.com/emails",
            request.RequestUri?.ToString());

        Assert.Equal(
            new AuthenticationHeaderValue(
                "Bearer",
                "test-resend-api-key"),
            request.Headers.Authorization);

        Assert.True(
            request.Headers.Contains(
                "Idempotency-Key"));

        var body =
            JsonDocument.Parse(
                Assert.IsType<string>(
                    handler.RequestBody));

        var root =
            body.RootElement;

        Assert.Equal(
            "Fasty <noreply@example.com>",
            root.GetProperty("from").GetString());

        Assert.Equal(
            "person+test@example.com",
            root.GetProperty("to")[0].GetString());

        var html =
            root.GetProperty("html").GetString();

        Assert.NotNull(html);

        const string hrefPrefix = "href=\"";

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

        var encodedHref =
            html[hrefStart..hrefEnd];

        var confirmationUri =
            new Uri(
                WebUtility.HtmlDecode(
                    encodedHref));

        var query =
            QueryHelpers.ParseQuery(
                confirmationUri.Query);

        Assert.Equal(
            "person+test@example.com",
            query["email"].ToString());

        Assert.Equal(
            "token/value+with=symbols",
            query["token"].ToString());
    }

    [Fact]
    public async Task Sender_posts_encoded_password_reset_email()
    {
        var handler =
            new CapturingHttpMessageHandler();

        using var client =
            new HttpClient(handler)
            {
                BaseAddress =
                    new Uri(
                        "https://api.resend.com/")
            };

        var sender =
            CreateSender(
                client);

        await sender.SendPasswordResetAsync(
            "person+test@example.com",
            "reset/token+with=symbols",
            TestContext.Current.CancellationToken);

        var request =
            Assert.IsType<HttpRequestMessage>(
                handler.Request);

        Assert.Equal(
            HttpMethod.Post,
            request.Method);

        Assert.True(
            request.Headers.TryGetValues(
                "Idempotency-Key",
                out var idempotencyKeys));

        Assert.StartsWith(
            "password_reset_",
            Assert.Single(idempotencyKeys));

        var body =
            JsonDocument.Parse(
                Assert.IsType<string>(
                    handler.RequestBody));

        var root =
            body.RootElement;

        Assert.Equal(
            "Reset your Fasty password",
            root.GetProperty("subject").GetString());

        var html =
            Assert.IsType<string>(
                root.GetProperty("html").GetString());

        const string hrefPrefix = "href=\"";

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

        var resetUri =
            new Uri(
                WebUtility.HtmlDecode(
                    html[hrefStart..hrefEnd]));

        Assert.Equal(
            "/reset-password",
            resetUri.AbsolutePath);

        var query =
            QueryHelpers.ParseQuery(
                resetUri.Query);

        Assert.Equal(
            "person+test@example.com",
            query["email"].ToString());

        Assert.Equal(
            "reset/token+with=symbols",
            query["token"].ToString());
    }
    [Fact]
    public async Task Sender_throws_for_unsuccessful_response()
    {
        var handler =
            new CapturingHttpMessageHandler(
                HttpStatusCode.BadRequest,
                """{"message":"invalid sender"}""");

        using var client =
            new HttpClient(handler)
            {
                BaseAddress =
                    new Uri(
                        "https://api.resend.com/")
            };

        var sender =
            CreateSender(
                client);

        var exception =
            await Assert.ThrowsAsync<HttpRequestException>(
                () => sender.SendVerificationAsync(
                    "person@example.com",
                    "confirmation-token",
                    TestContext.Current.CancellationToken));

        Assert.Equal(
            HttpStatusCode.BadRequest,
            exception.StatusCode);
        Assert.Equal(
            "Resend rejected the email request with status 400.",
            exception.Message);

        Assert.DoesNotContain(
            "invalid sender",
            exception.Message);
    }

    [Fact]
    public async Task Disabled_sender_does_not_make_http_request()
    {
        var handler =
            new CapturingHttpMessageHandler();

        using var client =
            new HttpClient(handler)
            {
                BaseAddress =
                    new Uri(
                        "https://api.resend.com/")
            };

        var sender =
            CreateSender(
                client,
                enabled: false);

        Assert.False(
            sender.IsAvailable);

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => sender.SendVerificationAsync(
                "person@example.com",
                "confirmation-token",
                TestContext.Current.CancellationToken));

        Assert.Null(
            handler.Request);
    }

    private static ResendAccountEmailSender CreateSender(
        HttpClient client,
        bool enabled = true)
    {
        return new ResendAccountEmailSender(
            client,
            Options.Create(
                new EmailDeliveryOptions
                {
                    Enabled = enabled,
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
                new ResendOptions
                {
                    ApiKey =
                        "test-resend-api-key"
                }));
    }
}
