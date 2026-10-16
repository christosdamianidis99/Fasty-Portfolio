using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Identity.Email;

public sealed class ResendAccountEmailSender(
    HttpClient httpClient,
    IOptions<EmailDeliveryOptions> deliveryOptionsAccessor,
    IOptions<ResendOptions> resendOptionsAccessor)
    : IAccountEmailSender
{
    private readonly EmailDeliveryOptions _deliveryOptions =
        deliveryOptionsAccessor.Value;

    private readonly ResendOptions _resendOptions =
        resendOptionsAccessor.Value;

    public bool IsAvailable =>
        _deliveryOptions.Enabled
        && !string.IsNullOrWhiteSpace(
            _resendOptions.ApiKey);

    public async Task SendVerificationAsync(
        string email,
        string confirmationToken,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!IsAvailable)
        {
            throw new InvalidOperationException(
                "Resend email delivery is not configured.");
        }

        var confirmationUrl =
            QueryHelpers.AddQueryString(
                _deliveryOptions.ConfirmationUrl,
                new Dictionary<string, string?>
                {
                    ["email"] = email,
                    ["token"] = confirmationToken
                });

        var encodedUrl =
            HtmlEncoder.Default.Encode(
                confirmationUrl);

        var requestBody = new
        {
            from =
                $"{_deliveryOptions.FromName} " +
                $"<{_deliveryOptions.FromAddress}>",
            to = new[]
            {
                email
            },
            subject = "Confirm your Fasty email",
            html =
                $"""
                <p>Welcome to Fasty.</p>
                <p>
                  <a href="{encodedUrl}">
                    Confirm your email address
                  </a>
                </p>
                <p>
                  If you did not create this account,
                  you can ignore this message.
                </p>
                """,
            text =
                $"""
                Welcome to Fasty.

                Confirm your email address:
                {confirmationUrl}

                If you did not create this account,
                you can ignore this message.
                """
        };

        using var request =
            new HttpRequestMessage(
                HttpMethod.Post,
                "emails");

        request.Headers.Authorization =
            new AuthenticationHeaderValue(
                "Bearer",
                _resendOptions.ApiKey);

        request.Headers.UserAgent.ParseAdd(
            "Fasty.Api/1.0");

        request.Headers.TryAddWithoutValidation(
            "Idempotency-Key",
            CreateIdempotencyKey(
                "email_confirmation",
                email,
                confirmationToken));

        request.Content =
            JsonContent.Create(
                requestBody);

        using var response =
            await httpClient.SendAsync(
                request,
                cancellationToken);

        if (response.IsSuccessStatusCode)
        {
            return;
        }

        throw new HttpRequestException(
            $"Resend rejected the email request " +
            $"with status {(int)response.StatusCode}.",
            inner: null,
            statusCode:
                response.StatusCode);
    }

    public async Task SendPasswordResetAsync(
        string email,
        string passwordResetToken,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!IsAvailable)
        {
            throw new InvalidOperationException(
                "Resend email delivery is not configured.");
        }

        var passwordResetUrl =
            QueryHelpers.AddQueryString(
                _deliveryOptions.PasswordResetUrl,
                new Dictionary<string, string?>
                {
                    ["email"] = email,
                    ["token"] = passwordResetToken
                });

        var encodedUrl =
            HtmlEncoder.Default.Encode(
                passwordResetUrl);

        var requestBody = new
        {
            from =
                $"{_deliveryOptions.FromName} " +
                $"<{_deliveryOptions.FromAddress}>",
            to = new[]
            {
                email
            },
            subject = "Reset your Fasty password",
            html =
                $"""
                <p>A password reset was requested for your Fasty account.</p>
                <p>
                  <a href="{encodedUrl}">
                    Reset your password
                  </a>
                </p>
                <p>
                  If you did not request this,
                  you can ignore this message.
                </p>
                """,
            text =
                $"""
                A password reset was requested for your Fasty account.

                Reset your password:
                {passwordResetUrl}

                If you did not request this,
                you can ignore this message.
                """
        };

        using var request =
            new HttpRequestMessage(
                HttpMethod.Post,
                "emails");

        request.Headers.Authorization =
            new AuthenticationHeaderValue(
                "Bearer",
                _resendOptions.ApiKey);

        request.Headers.UserAgent.ParseAdd(
            "Fasty.Api/1.0");

        request.Headers.TryAddWithoutValidation(
            "Idempotency-Key",
            CreateIdempotencyKey(
                "password_reset",
                email,
                passwordResetToken));

        request.Content =
            JsonContent.Create(
                requestBody);

        using var response =
            await httpClient.SendAsync(
                request,
                cancellationToken);

        if (response.IsSuccessStatusCode)
        {
            return;
        }

        throw new HttpRequestException(
            $"Resend rejected the email request " +
            $"with status {(int)response.StatusCode}.",
            inner: null,
            statusCode:
                response.StatusCode);
    }
    private static string CreateIdempotencyKey(
        string purpose,
        string email,
        string token)
    {
        var source =
            $"{purpose}:{email}:{token}";

        var hash =
            System.Security.Cryptography.SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes(
                    source));

        return $"{purpose}_{Convert.ToHexString(hash)}";
    }
}
