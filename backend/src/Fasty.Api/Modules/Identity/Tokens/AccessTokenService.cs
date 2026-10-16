using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace Fasty.Api.Modules.Identity.Tokens;

public sealed record AccessTokenResult(
    string Token,
    DateTimeOffset ExpiresAt);

public interface IAccessTokenService
{
    AccessTokenResult Generate(
        ApplicationUser user,
        DateTimeOffset issuedAt);
}

public sealed class AccessTokenService : IAccessTokenService
{
    private readonly TokenOptions _options;
    private readonly SigningCredentials _signingCredentials;

    public AccessTokenService(IOptions<TokenOptions> options)
    {
        _options = options.Value;

        ValidateOptions(_options);

        var signingKeyBytes = Encoding.UTF8.GetBytes(_options.SigningKey);
        var securityKey = new SymmetricSecurityKey(signingKeyBytes);

        _signingCredentials = new SigningCredentials(
            securityKey,
            SecurityAlgorithms.HmacSha256);
    }

    public AccessTokenResult Generate(
        ApplicationUser user,
        DateTimeOffset issuedAt)
    {
        ArgumentNullException.ThrowIfNull(user);

        var expiresAt = issuedAt.AddMinutes(_options.AccessTokenMinutes);

        var claims = new[]
        {
            new Claim(
                JwtRegisteredClaimNames.Sub,
                user.Id.ToString()),

            new Claim(
                JwtRegisteredClaimNames.Email,
                user.Email ?? string.Empty),

            new Claim(
                JwtRegisteredClaimNames.Jti,
                Guid.NewGuid().ToString()),

            new Claim(
                ClaimTypes.NameIdentifier,
                user.Id.ToString()),

            new Claim(
                ClaimTypes.Email,
                user.Email ?? string.Empty)
        };

        var token = new JwtSecurityToken(
            issuer: _options.Issuer,
            audience: _options.Audience,
            claims: claims,
            notBefore: issuedAt.UtcDateTime,
            expires: expiresAt.UtcDateTime,
            signingCredentials: _signingCredentials);

        var serializedToken =
            new JwtSecurityTokenHandler().WriteToken(token);

        return new AccessTokenResult(
            serializedToken,
            expiresAt);
    }

    private static void ValidateOptions(TokenOptions options)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(options.Issuer);
        ArgumentException.ThrowIfNullOrWhiteSpace(options.Audience);
        ArgumentException.ThrowIfNullOrWhiteSpace(options.SigningKey);

        if (Encoding.UTF8.GetByteCount(options.SigningKey) < 32)
        {
            throw new InvalidOperationException(
                "The JWT signing key must contain at least 32 bytes.");
        }

        if (options.AccessTokenMinutes is < 1 or > 60)
        {
            throw new InvalidOperationException(
                "AccessTokenMinutes must be between 1 and 60.");
        }

        if (options.RefreshTokenDays is < 1 or > 90)
        {
            throw new InvalidOperationException(
                "RefreshTokenDays must be between 1 and 90.");
        }
    }
}