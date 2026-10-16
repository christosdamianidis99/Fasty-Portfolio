using Fasty.Api.Modules.Identity.Email;
using Xunit;

namespace Fasty.Api.Tests.Identity;

public sealed class ResendOptionsValidatorTests
{
    private readonly ResendOptionsValidator _validator =
        new();

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Missing_api_key_fails(
        string apiKey)
    {
        var result =
            _validator.Validate(
                name: null,
                new ResendOptions
                {
                    ApiKey = apiKey
                });

        Assert.True(
            result.Failed);

        Assert.Contains(
            "ApiKey is required",
            Assert.Single(
                result.Failures));
    }

    [Fact]
    public void Configured_api_key_succeeds()
    {
        var result =
            _validator.Validate(
                name: null,
                new ResendOptions
                {
                    ApiKey =
                        "test-resend-api-key"
                });

        Assert.True(
            result.Succeeded);
    }
}
