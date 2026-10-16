using System.Diagnostics;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Monitoring;

public sealed class RequestMetricsMiddleware
{
    private const string UnmatchedRoute = "unmatched";

    private readonly RequestDelegate _next;
    private readonly IRequestMetricsStore _store;
    private readonly MonitoringOptions _options;

    public RequestMetricsMiddleware(
        RequestDelegate next,
        IRequestMetricsStore store,
        IOptions<MonitoringOptions> optionsAccessor)
    {
        ArgumentNullException.ThrowIfNull(next);
        ArgumentNullException.ThrowIfNull(store);
        ArgumentNullException.ThrowIfNull(optionsAccessor);

        _next = next;
        _store = store;
        _options = optionsAccessor.Value;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        if (!_options.Enabled
            || context.Request.Path.StartsWithSegments(
                "/monitoring",
                StringComparison.OrdinalIgnoreCase))
        {
            await _next(context);
            return;
        }

        _store.RequestStarted();

        var startedAt = Stopwatch.GetTimestamp();
        Exception? requestException = null;

        try
        {
            await _next(context);
        }
        catch (Exception exception)
        {
            requestException = exception;
            throw;
        }
        finally
        {
            var duration = Stopwatch.GetElapsedTime(startedAt);
            var statusCode = requestException is null
                ? context.Response.StatusCode
                : StatusCodes.Status500InternalServerError;

            var route = context.GetEndpoint() is RouteEndpoint routeEndpoint
                ? routeEndpoint.RoutePattern.RawText ?? UnmatchedRoute
                : UnmatchedRoute;

            _store.RequestCompleted(
                new RequestMetric(
                    TimestampUtc: DateTimeOffset.UtcNow,
                    Method: context.Request.Method,
                    Route: route,
                    StatusCode: statusCode,
                    DurationMilliseconds: duration.TotalMilliseconds,
                    AnonymizedUserId: GetAnonymizedUserId(context),
                    Failed: requestException is not null
                        || statusCode >= StatusCodes.Status500InternalServerError));
        }
    }

    private string? GetAnonymizedUserId(HttpContext context)
    {
        var userId = context.User.FindFirstValue(
            ClaimTypes.NameIdentifier);

        if (string.IsNullOrWhiteSpace(userId)
            || string.IsNullOrWhiteSpace(_options.AnonymizationKey))
        {
            return null;
        }

        var keyBytes = Encoding.UTF8.GetBytes(
            _options.AnonymizationKey);
        var userIdBytes = Encoding.UTF8.GetBytes(userId);

        var hash = HMACSHA256.HashData(
            keyBytes,
            userIdBytes);

        return Convert.ToHexString(hash)[..8]
            .ToLowerInvariant();
    }
}
