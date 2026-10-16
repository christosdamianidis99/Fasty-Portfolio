namespace Fasty.Api.Modules.Monitoring;

public interface IUserActionTracker
{
    Task TrackAsync(
        Guid userId,
        string action,
        CancellationToken cancellationToken = default);
}
