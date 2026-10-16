using Xunit;
using Fasty.Api.Modules.Monitoring;
using Microsoft.Extensions.Options;

namespace Fasty.Api.Tests.Monitoring;

public sealed class InMemoryRequestMetricsStoreTests
{
    [Fact]
    public void RequestStarted_IncrementsActiveRequestCount()
    {
        var store = CreateStore(capacity: 10);

        store.RequestStarted();

        Assert.Equal(1, store.ActiveRequests);
    }

    [Fact]
    public void RequestCompleted_StoresSafeMetadataAndDecrementsActiveCount()
    {
        var store = CreateStore(capacity: 10);

        store.RequestStarted();

        var metric = new RequestMetric(
            TimestampUtc: DateTimeOffset.Parse(
                "2026-08-04T20:00:00Z"),
            Method: "PUT",
            Route: "/api/v1/notes/{id:guid}",
            StatusCode: 200,
            DurationMilliseconds: 42.5,
            AnonymizedUserId: "usr_123456789abc",
            Failed: false);

        store.RequestCompleted(metric);

        var storedMetric = Assert.Single(store.GetRecent());

        Assert.Equal(metric, storedMetric);
        Assert.Equal(0, store.ActiveRequests);
    }

    [Fact]
    public void RequestCompleted_DropsOldestRecordsBeyondCapacity()
    {
        var store = CreateStore(capacity: 2);

        CompleteRequest(store, "/first");
        CompleteRequest(store, "/second");
        CompleteRequest(store, "/third");

        var metrics = store.GetRecent();

        Assert.Collection(
            metrics,
            metric => Assert.Equal("/second", metric.Route),
            metric => Assert.Equal("/third", metric.Route));
    }

    [Fact]
    public void Constructor_RejectsNonPositiveCapacity()
    {
        var options = Options.Create(
            new MonitoringOptions
            {
                RequestCapacity = 0
            });

        Assert.Throws<ArgumentOutOfRangeException>(
            () => new InMemoryRequestMetricsStore(options));
    }

    private static InMemoryRequestMetricsStore CreateStore(
        int capacity)
    {
        return new InMemoryRequestMetricsStore(
            Options.Create(
                new MonitoringOptions
                {
                    RequestCapacity = capacity
                }));
    }

    private static void CompleteRequest(
        InMemoryRequestMetricsStore store,
        string route)
    {
        store.RequestStarted();

        store.RequestCompleted(
            new RequestMetric(
                TimestampUtc: DateTimeOffset.UtcNow,
                Method: "GET",
                Route: route,
                StatusCode: 200,
                DurationMilliseconds: 1,
                AnonymizedUserId: null,
                Failed: false));
    }
}
