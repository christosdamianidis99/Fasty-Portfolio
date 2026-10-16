using System.Security.Cryptography;
using System.Text;

namespace Fasty.Api.Modules.Identity.Tokens;

public interface IRefreshTokenGenerator
{
    string Generate();

    string Hash(string refreshToken);
}

public sealed class RefreshTokenGenerator : IRefreshTokenGenerator
{
    private const int TokenSizeBytes = 64;

    public string Generate()
    {
        var tokenBytes = RandomNumberGenerator.GetBytes(TokenSizeBytes);

        return Convert.ToBase64String(tokenBytes)
            .Replace("+", "-", StringComparison.Ordinal)
            .Replace("/", "_", StringComparison.Ordinal)
            .TrimEnd('=');
    }

    public string Hash(string refreshToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(refreshToken);

        var tokenBytes = Encoding.UTF8.GetBytes(refreshToken);
        var hashBytes = SHA256.HashData(tokenBytes);

        return Convert.ToHexString(hashBytes);
    }
}