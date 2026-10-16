using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Monitoring;

public static class MonitoringEndpoints
{
    private const int MonitoringPort = 8081;
    private const int MaximumRequestLimit = 500;

    public static IEndpointRouteBuilder MapMonitoringEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var group = endpoints.MapGroup("/monitoring");

        group.MapGet(
            "/",
            (HttpContext context, IOptions<MonitoringOptions> optionsAccessor) =>
            {
                if (!CanAccess(context, optionsAccessor.Value))
                {
                    return Results.NotFound();
                }

                return Results.Content(
                    MonitoringDashboardPage.Render(),
                    "text/html; charset=utf-8");
            });

        group.MapGet(
            "/summary",
            (
                HttpContext context,
                IRequestMetricsStore store,
                IOptions<MonitoringOptions> optionsAccessor) =>
            {
                if (!CanAccess(context, optionsAccessor.Value))
                {
                    return Results.NotFound();
                }

                var requests = store.GetRecent();
                var failedRequests = requests.Count(request => request.Failed);

                var averageDurationMilliseconds = requests.Count == 0
                    ? 0
                    : requests.Average(
                        request => request.DurationMilliseconds);

                return Results.Ok(
                    new MonitoringSummaryResponse(
                        GeneratedAtUtc: DateTimeOffset.UtcNow,
                        ActiveRequests: store.ActiveRequests,
                        StoredRequests: requests.Count,
                        FailedRequests: failedRequests,
                        AverageDurationMilliseconds:
                            averageDurationMilliseconds));
            });

        group.MapGet(
            "/requests",
            (
                HttpContext context,
                IRequestMetricsStore store,
                IOptions<MonitoringOptions> optionsAccessor,
                int? limit) =>
            {
                if (!CanAccess(context, optionsAccessor.Value))
                {
                    return Results.NotFound();
                }

                var resolvedLimit = Math.Clamp(
                    limit ?? 100,
                    1,
                    MaximumRequestLimit);

                var requests = store
                    .GetRecent()
                    .TakeLast(resolvedLimit)
                    .Reverse()
                    .ToArray();

                return Results.Ok(requests);
            });

        return endpoints;
    }

    private static bool CanAccess(
        HttpContext context,
        MonitoringOptions options)
    {
        return options.Enabled
            && context.Connection.LocalPort == MonitoringPort;
    }

    private sealed record MonitoringSummaryResponse(
        DateTimeOffset GeneratedAtUtc,
        int ActiveRequests,
        int StoredRequests,
        int FailedRequests,
        double AverageDurationMilliseconds);
}
