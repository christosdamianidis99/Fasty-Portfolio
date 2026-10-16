using Fasty.Api.Modules.Identity.Email;
using Xunit;

namespace Fasty.Api.Tests.Identity;

public sealed class EmailDeliveryOptionsValidatorTests
{
    private readonly EmailDeliveryOptionsValidator _validator =
        new();

    [Fact]
    public void Disabled_delivery_does_not_require_configuration()
    {
        var result =
            _validator.Validate(
                null,
                new EmailDeliveryOptions());

        Assert.True(result.Succeeded);
    }

    [Fact]
    public void Enabled_delivery_requires_complete_configuration()
    {
        var result =
            _validator.Validate(
                null,
                new EmailDeliveryOptions
                {
                    Enabled = true
                });

        Assert.True(result.Failed);

        Assert.Contains(
            result.Failures,
            failure =>
                failure.Contains(
                    "sender address",
                    StringComparison.OrdinalIgnoreCase));

        Assert.Contains(
            result.Failures,
            failure =>
                failure.Contains(
                    "confirmation URL",
                    StringComparison.OrdinalIgnoreCase));

        Assert.Contains(
            result.Failures,
            failure =>
                failure.Contains(
                    "password reset URL",
                    StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Enabled_delivery_accepts_default_resend_provider()
    {
        var result =
            _validator.Validate(
                null,
                ValidOptions());

        Assert.True(result.Succeeded);
    }

    [Theory]
    [InlineData("Resend")]
    [InlineData("resend")]
    [InlineData("Smtp")]
    [InlineData("smtp")]
    public void Enabled_delivery_accepts_supported_provider(
        string provider)
    {
        var options =
            ValidOptions(
                provider);

        var result =
            _validator.Validate(
                null,
                options);

        Assert.True(result.Succeeded);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("Unknown")]
    public void Enabled_delivery_rejects_unsupported_provider(
        string provider)
    {
        var options =
            ValidOptions(
                provider);

        var result =
            _validator.Validate(
                null,
                options);

        Assert.True(result.Failed);

        Assert.Contains(
            result.Failures,
            failure =>
                failure.Contains(
                    "provider",
                    StringComparison.OrdinalIgnoreCase));
    }

    [Theory]
    [InlineData("")]
    [InlineData("not-an-email")]
    [InlineData("Fasty <noreply@example.com>")]
    public void Enabled_delivery_rejects_invalid_sender_address(
        string fromAddress)
    {
        var options =
            ValidOptions();

        options = new EmailDeliveryOptions
        {
            Enabled = options.Enabled,
            Provider = options.Provider,
            FromAddress = fromAddress,
            FromName = options.FromName,
            ConfirmationUrl = options.ConfirmationUrl,
            PasswordResetUrl = options.PasswordResetUrl
        };

        var result =
            _validator.Validate(
                null,
                options);

        Assert.True(result.Failed);

        Assert.Contains(
            result.Failures,
            failure =>
                failure.Contains(
                    "sender address",
                    StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Enabled_delivery_accepts_fasty_account_links()
    {
        var options = new EmailDeliveryOptions
        {
            Enabled = true,
            Provider = EmailProviderNames.Smtp,
            FromAddress = "noreply@example.com",
            FromName = "Fasty",
            ConfirmationUrl =
                "fasty://account/confirm-email",
            PasswordResetUrl =
                "fasty://account/reset-password"
        };

        var result =
            _validator.Validate(
                null,
                options);

        Assert.True(result.Succeeded);
    }

    [Theory]
    [InlineData("")]
    [InlineData("confirm-email")]
    [InlineData("ftp://example.com/confirm-email")]
    [InlineData("fasty://other/confirm-email")]
    [InlineData("fasty://account/reset-password")]
    [InlineData("fasty://account/confirm-email?source=test")]
    public void Enabled_delivery_rejects_invalid_confirmation_url(
        string confirmationUrl)
    {
        var options =
            ValidOptions();

        options = new EmailDeliveryOptions
        {
            Enabled = options.Enabled,
            Provider = options.Provider,
            FromAddress = options.FromAddress,
            FromName = options.FromName,
            ConfirmationUrl = confirmationUrl,
            PasswordResetUrl = options.PasswordResetUrl
        };

        var result =
            _validator.Validate(
                null,
                options);

        Assert.True(result.Failed);

        Assert.Contains(
            result.Failures,
            failure =>
                failure.Contains(
                    "confirmation URL",
                    StringComparison.OrdinalIgnoreCase));
    }

    [Theory]
    [InlineData("")]
    [InlineData("reset-password")]
    [InlineData("ftp://example.com/reset-password")]
    [InlineData("fasty://other/reset-password")]
    [InlineData("fasty://account/confirm-email")]
    [InlineData("fasty://account/reset-password#fragment")]
    public void Enabled_delivery_rejects_invalid_password_reset_url(
        string passwordResetUrl)
    {
        var options =
            ValidOptions();

        options = new EmailDeliveryOptions
        {
            Enabled = options.Enabled,
            Provider = options.Provider,
            FromAddress = options.FromAddress,
            FromName = options.FromName,
            ConfirmationUrl = options.ConfirmationUrl,
            PasswordResetUrl = passwordResetUrl
        };

        var result =
            _validator.Validate(
                null,
                options);

        Assert.True(result.Failed);

        Assert.Contains(
            result.Failures,
            failure =>
                failure.Contains(
                    "password reset URL",
                    StringComparison.OrdinalIgnoreCase));
    }

    private static EmailDeliveryOptions ValidOptions(
        string provider =
            EmailProviderNames.Resend)
    {
        return new EmailDeliveryOptions
        {
            Enabled = true,
            Provider = provider,
            FromAddress = "noreply@example.com",
            FromName = "Fasty",
            ConfirmationUrl =
                "https://app.example.com/confirm-email",
            PasswordResetUrl =
                "https://app.example.com/reset-password"
        };
    }
}
