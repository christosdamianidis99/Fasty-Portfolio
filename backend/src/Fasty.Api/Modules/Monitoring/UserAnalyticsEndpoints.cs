using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Monitoring;

public static class UserAnalyticsEndpoints
{
    private const int PrivateMonitoringPort = 8081;

    public static IEndpointRouteBuilder
        MapUserAnalyticsEndpoints(
            this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet(
            "/monitoring/analytics",
            (
                HttpContext context,
                IOptions<MonitoringOptions> optionsAccessor) =>
            {
                if (!CanAccess(
                        context,
                        optionsAccessor.Value))
                {
                    return Results.NotFound();
                }

                return Results.Content(
                    UserAnalyticsDashboardPage.Html,
                    "text/html; charset=utf-8");
            });

        endpoints.MapGet(
            "/monitoring/users",
            (
                HttpContext context,
                IOptions<MonitoringOptions> optionsAccessor) =>
            {
                if (!CanAccess(
                        context,
                        optionsAccessor.Value))
                {
                    return Results.NotFound();
                }

                return Results.Content(
                    UserDetailsDashboardPage.Html,
                    "text/html; charset=utf-8");
            });

        endpoints.MapGet(
            "/monitoring/actions",
            async (
                HttpContext context,
                IUserActionStore store,
                IOptions<MonitoringOptions> optionsAccessor,
                int limit,
                CancellationToken cancellationToken) =>
            {
                if (!CanAccess(
                        context,
                        optionsAccessor.Value))
                {
                    return Results.NotFound();
                }

                var actions =
                    await store.GetRecentAsync(
                        limit == 0 ? 50 : limit,
                        cancellationToken);

                return Results.Ok(actions);
            });

        endpoints.MapGet(
            "/monitoring/actions/summary",
            async (
                HttpContext context,
                IUserActionStore store,
                IOptions<MonitoringOptions> optionsAccessor,
                CancellationToken cancellationToken) =>
            {
                if (!CanAccess(
                        context,
                        optionsAccessor.Value))
                {
                    return Results.NotFound();
                }

                return Results.Ok(
                    await store.GetSummaryAsync(
                        cancellationToken));
            });

        endpoints.MapGet(
            "/monitoring/users/list",
            async (
                HttpContext context,
                IUserActionStore store,
                IOptions<MonitoringOptions> optionsAccessor,
                CancellationToken cancellationToken) =>
            {
                if (!CanAccess(
                        context,
                        optionsAccessor.Value))
                {
                    return Results.NotFound();
                }

                return Results.Ok(
                    await store.GetUsersAsync(
                        cancellationToken));
            });

        endpoints.MapGet(
            "/monitoring/users/{anonymizedUserId}",
            async (
                string anonymizedUserId,
                HttpContext context,
                IUserActionStore store,
                IOptions<MonitoringOptions> optionsAccessor,
                CancellationToken cancellationToken) =>
            {
                if (!CanAccess(
                        context,
                        optionsAccessor.Value))
                {
                    return Results.NotFound();
                }

                var user =
                    await store.GetUserAsync(
                        anonymizedUserId,
                        cancellationToken);

                return user is null
                    ? Results.NotFound()
                    : Results.Ok(user);
            });

        endpoints.MapGet(
            "/monitoring/users/{anonymizedUserId}/actions",
            async (
                string anonymizedUserId,
                HttpContext context,
                IUserActionStore store,
                IOptions<MonitoringOptions> optionsAccessor,
                int limit,
                CancellationToken cancellationToken) =>
            {
                if (!CanAccess(
                        context,
                        optionsAccessor.Value))
                {
                    return Results.NotFound();
                }

                var actions =
                    await store.GetRecentForUserAsync(
                        anonymizedUserId,
                        limit == 0 ? 100 : limit,
                        cancellationToken);

                return Results.Ok(actions);
            });

        return endpoints;
    }

    private static bool CanAccess(
        HttpContext context,
        MonitoringOptions options)
    {
        return options.Enabled
            && context.Connection.LocalPort
                == PrivateMonitoringPort;
    }
}
