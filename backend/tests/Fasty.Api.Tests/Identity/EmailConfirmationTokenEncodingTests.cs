using System.Text;
using Microsoft.AspNetCore.WebUtilities;
using Xunit;

namespace Fasty.Api.Tests.Identity;

public sealed class EmailConfirmationTokenEncodingTests
{
    [Fact]
    public void EncodedToken_RoundTripsToOriginalValue()
    {
        const string originalToken =
            "sample+identity/token=value==";

        var encoded = WebEncoders.Base64UrlEncode(
            Encoding.UTF8.GetBytes(originalToken));

        var decodedBytes =
            WebEncoders.Base64UrlDecode(encoded);

        var decoded =
            Encoding.UTF8.GetString(decodedBytes);

        Assert.Equal(originalToken, decoded);
    }

    [Fact]
    public void EncodedToken_IsUrlSafe()
    {
        const string originalToken =
            "sample+identity/token=value==";

        var encoded = WebEncoders.Base64UrlEncode(
            Encoding.UTF8.GetBytes(originalToken));

        Assert.DoesNotContain("+", encoded);
        Assert.DoesNotContain("/", encoded);
        Assert.DoesNotContain("=", encoded);
    }

    [Fact]
    public void InvalidToken_ThrowsFormatException()
    {
        Assert.Throws<FormatException>(() =>
            WebEncoders.Base64UrlDecode("%%%invalid%%%"));
    }
}