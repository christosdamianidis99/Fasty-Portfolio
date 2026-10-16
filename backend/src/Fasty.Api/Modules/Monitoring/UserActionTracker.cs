using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Monitoring;

public sealed class UserActionTracker
    : IUserActionTracker
{
    private readonly IUserActionStore _store;
    private readonly MonitoringOptions _options;

    public UserActionTracker(
        IUserActionStore store,
        IOptions<MonitoringOptions> optionsAccessor)
    {
        ArgumentNullException.ThrowIfNull(store);
        ArgumentNullException.ThrowIfNull(optionsAccessor);

        _store = store;
        _options = optionsAccessor.Value;
    }

    public async Task TrackAsync(
        Guid userId,
        string action,
        CancellationToken cancellationToken = default)
    {
        if (!_options.Enabled
            || userId == Guid.Empty
            || string.IsNullOrWhiteSpace(action)
            || string.IsNullOrWhiteSpace(
                _options.AnonymizationKey))
        {
            return;
        }

        var keyBytes = Encoding.UTF8.GetBytes(
            _options.AnonymizationKey);

        var userIdBytes = Encoding.UTF8.GetBytes(
            userId.ToString("D"));

        var hash = HMACSHA256.HashData(
            keyBytes,
            userIdBytes);

        var anonymizedUserId =
            Convert.ToHexString(hash)[..8]
                .ToLowerInvariant();

        await _store.AddAsync(
            new UserActionMetric(
                TimestampUtc: DateTimeOffset.UtcNow,
                Action: action,
                AnonymizedUserId: anonymizedUserId),
            cancellationToken);
    }
}
