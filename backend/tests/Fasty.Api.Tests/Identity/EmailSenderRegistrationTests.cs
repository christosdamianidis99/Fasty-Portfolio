using Fasty.Api.Modules.Identity.Email;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Xunit;

namespace Fasty.Api.Tests.Identity;

public sealed class EmailSenderRegistrationTests
{
    [Fact]
    public void Development_uses_development_sender()
    {
        using var factory =
            new EmailSenderFactory(
                environment: "Development",
                deliveryEnabled: false);

        var sender =
            factory.Services
                .GetRequiredService<IAccountEmailSender>();

        Assert.IsType<DevelopmentAccountEmailSender>(
            sender);
    }

    [Fact]
    public void Production_with_delivery_disabled_uses_unavailable_sender()
    {
        using var factory =
            new EmailSenderFactory(
                environment: "Production",
                deliveryEnabled: false);

        var sender =
            factory.Services
                .GetRequiredService<IAccountEmailSender>();

        Assert.IsType<UnavailableAccountEmailSender>(
            sender);
    }

    [Fact]
    public void Production_with_resend_uses_resend_sender()
    {
        using var factory =
            new EmailSenderFactory(
                environment: "Production",
                deliveryEnabled: true,
                provider:
                    EmailProviderNames.Resend,
                resendApiKey:
                    "test-resend-api-key");

        var sender =
            factory.Services
                .GetRequiredService<IAccountEmailSender>();

        Assert.IsType<ResendAccountEmailSender>(
            sender);
    }

    [Fact]
    public void Production_with_resend_and_missing_api_key_fails_startup()
    {
        using var factory =
            new EmailSenderFactory(
                environment: "Production",
                deliveryEnabled: true,
                provider:
                    EmailProviderNames.Resend);

        var exception =
            Assert.Throws<OptionsValidationException>(
                () => _ = factory.Services);

        Assert.Contains(
            exception.Failures,
            failure =>
                failure.Contains(
                    "Email:Resend:ApiKey is required",
                    StringComparison.Ordinal));
    }

    [Fact]
    public void Production_with_smtp_uses_smtp_sender()
    {
        using var factory =
            new EmailSenderFactory(
                environment: "Production",
                deliveryEnabled: true,
                provider:
                    EmailProviderNames.Smtp,
                smtpHost:
                    "smtp-relay.brevo.com",
                smtpUsername:
                    "smtp-user",
                smtpPassword:
                    "smtp-password");

        var sender =
            factory.Services
                .GetRequiredService<IAccountEmailSender>();

        Assert.IsType<SmtpAccountEmailSender>(
            sender);

        var transport =
            factory.Services
                .GetRequiredService<ISmtpEmailTransport>();

        Assert.IsType<MailKitSmtpEmailTransport>(
            transport);
    }

    [Fact]
    public void Production_with_smtp_and_missing_configuration_fails_startup()
    {
        using var factory =
            new EmailSenderFactory(
                environment: "Production",
                deliveryEnabled: true,
                provider:
                    EmailProviderNames.Smtp);

        var exception =
            Assert.Throws<OptionsValidationException>(
                () => _ = factory.Services);

        Assert.Contains(
            exception.Failures,
            failure =>
                failure.Contains(
                    "Email:Smtp:Host is required",
                    StringComparison.Ordinal));

        Assert.Contains(
            exception.Failures,
            failure =>
                failure.Contains(
                    "Email:Smtp:Username is required",
                    StringComparison.Ordinal));

        Assert.Contains(
            exception.Failures,
            failure =>
                failure.Contains(
                    "Email:Smtp:Password is required",
                    StringComparison.Ordinal));
    }

    [Fact]
    public void Production_with_unsupported_provider_fails_startup()
    {
        using var factory =
            new EmailSenderFactory(
                environment: "Production",
                deliveryEnabled: true,
                provider:
                    "Unknown");

        var exception =
            Assert.Throws<OptionsValidationException>(
                () => _ = factory.Services);

        Assert.Contains(
            exception.Failures,
            failure =>
                failure.Contains(
                    "provider",
                    StringComparison.OrdinalIgnoreCase));
    }

    private sealed class EmailSenderFactory(
        string environment,
        bool deliveryEnabled,
        string provider =
            EmailProviderNames.Resend,
        string resendApiKey = "",
        string smtpHost = "",
        string smtpUsername = "",
        string smtpPassword = "")
        : WebApplicationFactory<Program>
    {
        private const string TestSigningKey =
            "fasty-email-registration-tests-signing-key-2026-secure-value";

        private readonly string _environment =
            environment;

        private readonly bool _deliveryEnabled =
            deliveryEnabled;

        private readonly string _provider =
            provider;

        private readonly string _resendApiKey =
            resendApiKey;

        private readonly string _smtpHost =
            smtpHost;

        private readonly string _smtpUsername =
            smtpUsername;

        private readonly string _smtpPassword =
            smtpPassword;

        protected override void ConfigureWebHost(
            IWebHostBuilder builder)
        {
            builder.UseEnvironment(
                _environment);

            builder.UseSetting(
                $"{EmailDeliveryOptions.SectionName}:Enabled",
                _deliveryEnabled.ToString());

            builder.UseSetting(
                $"{EmailDeliveryOptions.SectionName}:Provider",
                _provider);

            builder.UseSetting(
                $"{ResendOptions.SectionName}:ApiKey",
                _resendApiKey);

            builder.UseSetting(
                $"{SmtpOptions.SectionName}:Host",
                _smtpHost);

            builder.UseSetting(
                $"{SmtpOptions.SectionName}:Port",
                "587");

            builder.UseSetting(
                $"{SmtpOptions.SectionName}:Username",
                _smtpUsername);

            builder.UseSetting(
                $"{SmtpOptions.SectionName}:Password",
                _smtpPassword);

            builder.UseSetting(
                $"{SmtpOptions.SectionName}:UseStartTls",
                "true");

            builder.ConfigureAppConfiguration(
                (_, configuration) =>
                {
                    configuration.AddInMemoryCollection(
                        new Dictionary<string, string?>
                        {
                            ["ConnectionStrings:FastyDatabase"] =
                                Environment.GetEnvironmentVariable(
                                    "FASTY_TEST_DATABASE")
                                ?? "Host=127.0.0.1;Port=5432;Database=fasty_tests;Username=postgres;Password=postgres",
                            ["Authentication:Tokens:Issuer"] =
                                "Fasty.Tests",
                            ["Authentication:Tokens:Audience"] =
                                "Fasty.Tests.Client",
                            ["Authentication:Tokens:SigningKey"] =
                                TestSigningKey,
                            ["Authentication:Registration:Enabled"] =
                                "false",
                            ["Email:Delivery:FromAddress"] =
                                "noreply@example.com",
                            ["Email:Delivery:FromName"] =
                                "Fasty",
                            ["Email:Delivery:ConfirmationUrl"] =
                                "https://app.example.com/confirm-email",
                            ["Email:Delivery:PasswordResetUrl"] =
                                "https://app.example.com/reset-password"
                        });
                });
        }
    }
}