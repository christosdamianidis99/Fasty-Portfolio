using Fasty.Api.Modules.Identity.Tokens;
using Xunit;

namespace Fasty.Api.Tests.Identity;

public sealed class RefreshTokenGeneratorTests
{
    private readonly RefreshTokenGenerator _generator = new();

    [Fact]
    public void Generate_ReturnsDifferentTokens()
    {
        var first = _generator.Generate();
        var second = _generator.Generate();

        Assert.NotEqual(first, second);
    }

    [Fact]
    public void Generate_ReturnsUrlSafeToken()
    {
        var token = _generator.Generate();

        Assert.DoesNotContain("+", token);
        Assert.DoesNotContain("/", token);
        Assert.DoesNotContain("=", token);
    }

    [Fact]
    public void Hash_ReturnsStableSha256Hex()
    {
        const string token = "test-refresh-token";

        var first = _generator.Hash(token);
        var second = _generator.Hash(token);

        Assert.Equal(first, second);
        Assert.Equal(64, first.Length);
    }

    [Fact]
    public void Hash_ReturnsDifferentValuesForDifferentTokens()
    {
        var first = _generator.Hash("token-one");
        var second = _generator.Hash("token-two");

        Assert.NotEqual(first, second);
    }
}