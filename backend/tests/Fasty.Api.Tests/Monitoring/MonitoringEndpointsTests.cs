using System.Net;
using System.Net.Http.Json;
using Fasty.Api.Modules.Monitoring;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Xunit;

namespace Fasty.Api.Tests.Monitoring;

public sealed class MonitoringEndpointsTests
{
    [Fact]
    public async Task Dashboard_OnMonitoringPort_ReturnsHtml()
    {
        await using var application = await CreateApplicationAsync(
            enabled: true,
            localPort: 8081);

        var client = application.GetTestClient();

        var response = await client.GetAsync("/monitoring");

        response.EnsureSuccessStatusCode();
        Assert.Equal("text/html; charset=utf-8",
            response.Content.Headers.ContentType?.ToString());

        var html = await response.Content.ReadAsStringAsync();

        Assert.Contains("Fasty Monitoring", html);
        Assert.Contains("/monitoring/summary", html);
        Assert.Contains("/monitoring/requests?limit=20", html);
    }

    [Fact]
    public async Task Summary_WhenMonitoringIsDisabled_ReturnsNotFound()
    {
        await using var application = await CreateApplicationAsync(
            enabled: false,
            localPort: 8081);

        var client = application.GetTestClient();

        var response = await client.GetAsync("/monitoring/summary");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Summary_OnPublicPort_ReturnsNotFound()
    {
        await using var application = await CreateApplicationAsync(
            enabled: true,
            localPort: 8080);

        var client = application.GetTestClient();

        var response = await client.GetAsync("/monitoring/summary");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Summary_OnMonitoringPort_ReturnsAggregateMetadata()
    {
        await using var application = await CreateApplicationAsync(
            enabled: true,
            localPort: 8081);

        var store = application.Services
            .GetRequiredService<IRequestMetricsStore>();

        store.RequestStarted();
        store.RequestCompleted(
            new RequestMetric(
                TimestampUtc: DateTimeOffset.UtcNow,
                Method: HttpMethods.Get,
                Route: "/health",
                StatusCode: StatusCodes.Status200OK,
                DurationMilliseconds: 12.5,
                AnonymizedUserId: null,
                Failed: false));

        var client = application.GetTestClient();

        var response = await client.GetAsync("/monitoring/summary");

        response.EnsureSuccessStatusCode();

        var summary =
            await response.Content.ReadFromJsonAsync<SummaryResponse>();

        Assert.NotNull(summary);
        Assert.Equal(0, summary.ActiveRequests);
        Assert.Equal(1, summary.StoredRequests);
        Assert.Equal(0, summary.FailedRequests);
        Assert.Equal(12.5, summary.AverageDurationMilliseconds);
    }

    [Fact]
    public async Task Requests_ReturnsNewestFirstAndAppliesLimit()
    {
        await using var application = await CreateApplicationAsync(
            enabled: true,
            localPort: 8081);

        var store = application.Services
            .GetRequiredService<IRequestMetricsStore>();

        AddMetric(store, "/first");
        AddMetric(store, "/second");
        AddMetric(store, "/third");

        var client = application.GetTestClient();

        var response =
            await client.GetAsync("/monitoring/requests?limit=2");

        response.EnsureSuccessStatusCode();

        var requests =
            await response.Content.ReadFromJsonAsync<RequestMetric[]>();

        Assert.NotNull(requests);
        Assert.Equal(2, requests.Length);
        Assert.Equal("/third", requests[0].Route);
        Assert.Equal("/second", requests[1].Route);
    }

    private static async Task<WebApplication> CreateApplicationAsync(
        bool enabled,
        int localPort)
    {
        var builder = WebApplication.CreateBuilder();

        builder.WebHost.UseTestServer();

        builder.Services.AddSingleton(
            Options.Create(
                new MonitoringOptions
                {
                    Enabled = enabled,
                    RequestCapacity = 100
                }));

        builder.Services.AddSingleton<
            IRequestMetricsStore,
            InMemoryRequestMetricsStore>();

        var application = builder.Build();

        application.Use(
            async (context, next) =>
            {
                context.Connection.LocalPort = localPort;
                await next(context);
            });

        application.MapMonitoringEndpoints();

        await application.StartAsync();

        return application;
    }

    private static void AddMetric(
        IRequestMetricsStore store,
        string route)
    {
        store.RequestStarted();
        store.RequestCompleted(
            new RequestMetric(
                TimestampUtc: DateTimeOffset.UtcNow,
                Method: HttpMethods.Get,
                Route: route,
                StatusCode: StatusCodes.Status200OK,
                DurationMilliseconds: 1,
                AnonymizedUserId: null,
                Failed: false));
    }

    private sealed record SummaryResponse(
        DateTimeOffset GeneratedAtUtc,
        int ActiveRequests,
        int StoredRequests,
        int FailedRequests,
        double AverageDurationMilliseconds);
}
