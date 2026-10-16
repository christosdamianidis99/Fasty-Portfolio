namespace Fasty.Api.Modules.Monitoring;

public interface IRequestMetricsStore
{
    int ActiveRequests { get; }

    void RequestStarted();

    void RequestCompleted(RequestMetric metric);

    IReadOnlyList<RequestMetric> GetRecent();
}
