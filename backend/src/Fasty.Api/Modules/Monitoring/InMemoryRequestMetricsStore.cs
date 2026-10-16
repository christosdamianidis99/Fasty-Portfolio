using System.Collections.Concurrent;
using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Monitoring;

public sealed class InMemoryRequestMetricsStore
    : IRequestMetricsStore
{
    private readonly ConcurrentQueue<RequestMetric> _requests = new();
    private readonly int _requestCapacity;

    private int _activeRequests;
    private int _storedRequestCount;

    public InMemoryRequestMetricsStore(
        IOptions<MonitoringOptions> optionsAccessor)
    {
        ArgumentNullException.ThrowIfNull(optionsAccessor);

        var options = optionsAccessor.Value;

        if (options.RequestCapacity <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(optionsAccessor),
                options.RequestCapacity,
                "Monitoring request capacity must be greater than zero.");
        }

        _requestCapacity = options.RequestCapacity;
    }

    public int ActiveRequests =>
        Volatile.Read(ref _activeRequests);

    public void RequestStarted()
    {
        Interlocked.Increment(ref _activeRequests);
    }

    public void RequestCompleted(RequestMetric metric)
    {
        ArgumentNullException.ThrowIfNull(metric);

        _requests.Enqueue(metric);
        Interlocked.Increment(ref _storedRequestCount);

        TrimToCapacity();

        Interlocked.Decrement(ref _activeRequests);
    }

    public IReadOnlyList<RequestMetric> GetRecent()
    {
        return _requests.ToArray();
    }

    private void TrimToCapacity()
    {
        while (Volatile.Read(ref _storedRequestCount)
               > _requestCapacity
               && _requests.TryDequeue(out _))
        {
            Interlocked.Decrement(ref _storedRequestCount);
        }
    }
}
