using Fasty.Api.Modules.Identity.Email;
using Xunit;

namespace Fasty.Api.Tests.Identity;

public sealed class SmtpOptionsValidatorTests
{
    private readonly SmtpOptionsValidator _validator =
        new();

    [Fact]
    public void Complete_configuration_succeeds()
    {
        var result =
            _validator.Validate(
                null,
                ValidOptions());

        Assert.True(
            result.Succeeded);
    }

    [Fact]
    public void Missing_required_configuration_fails()
    {
        var result =
            _validator.Validate(
                null,
                new SmtpOptions
                {
                    Port = 587
                });

        Assert.True(
            result.Failed);

        Assert.Contains(
            result.Failures,
            failure =>
                failure.Contains(
                    "Host",
                    StringComparison.Ordinal));

        Assert.Contains(
            result.Failures,
            failure =>
                failure.Contains(
                    "Username",
                    StringComparison.Ordinal));

        Assert.Contains(
            result.Failures,
            failure =>
                failure.Contains(
                    "Password",
                    StringComparison.Ordinal));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(65536)]
    public void Invalid_port_fails(
        int port)
    {
        var options =
            new SmtpOptions
            {
                Host =
                    "smtp-relay.brevo.com",
                Port =
                    port,
                Username =
                    "smtp-user",
                Password =
                    "smtp-password"
            };

        var result =
            _validator.Validate(
                null,
                options);

        Assert.True(
            result.Failed);

        Assert.Contains(
            result.Failures,
            failure =>
                failure.Contains(
                    "Port",
                    StringComparison.Ordinal));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(587)]
    [InlineData(65535)]
    public void Valid_port_succeeds(
        int port)
    {
        var options =
            new SmtpOptions
            {
                Host =
                    "smtp-relay.brevo.com",
                Port =
                    port,
                Username =
                    "smtp-user",
                Password =
                    "smtp-password"
            };

        var result =
            _validator.Validate(
                null,
                options);

        Assert.True(
            result.Succeeded);
    }

    private static SmtpOptions ValidOptions()
    {
        return new SmtpOptions
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
        };
    }
}