using System.Security.Claims;
using Fasty.Api.Modules.Monitoring;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.Routing.Patterns;
using Microsoft.Extensions.Options;
using Xunit;

namespace Fasty.Api.Tests.Monitoring;

public sealed class RequestMetricsMiddlewareTests
{
    [Fact]
    public async Task InvokeAsync_WhenDisabled_DoesNotCollectRequest()
    {
        var store = CreateStore();
        var nextWasCalled = false;

        var middleware = CreateMiddleware(
            async _ =>
            {
                nextWasCalled = true;
                await Task.CompletedTask;
            },
            store,
            enabled: false);

        await middleware.InvokeAsync(new DefaultHttpContext());

        Assert.True(nextWasCalled);
        Assert.Empty(store.GetRecent());
        Assert.Equal(0, store.ActiveRequests);
    }

    [Fact]
    public async Task InvokeAsync_ForMonitoringPath_DoesNotCollectRequest()
    {
        var store = CreateStore();

        var middleware = CreateMiddleware(
            _ => Task.CompletedTask,
            store,
            enabled: true);

        var context = new DefaultHttpContext();
        context.Request.Path = "/monitoring/summary";

        await middleware.InvokeAsync(context);

        Assert.Empty(store.GetRecent());
        Assert.Equal(0, store.ActiveRequests);
    }

    [Fact]
    public async Task InvokeAsync_StoresRouteTemplateInsteadOfRawPath()
    {
        var store = CreateStore();

        var middleware = CreateMiddleware(
            context =>
            {
                context.Response.StatusCode = StatusCodes.Status204NoContent;
                return Task.CompletedTask;
            },
            store,
            enabled: true);

        var context = new DefaultHttpContext();
        context.Request.Method = HttpMethods.Put;
        context.Request.Path = "/api/v1/notes/real-secret-note-id";
        context.SetEndpoint(
            new RouteEndpoint(
                _ => Task.CompletedTask,
                RoutePatternFactory.Parse("/api/v1/notes/{id:guid}"),
                order: 0,
                new EndpointMetadataCollection(),
                displayName: "Update note"));

        await middleware.InvokeAsync(context);

        var metric = Assert.Single(store.GetRecent());

        Assert.Equal(HttpMethods.Put, metric.Method);
        Assert.Equal("/api/v1/notes/{id:guid}", metric.Route);
        Assert.DoesNotContain("real-secret-note-id", metric.Route);
        Assert.Equal(StatusCodes.Status204NoContent, metric.StatusCode);
        Assert.False(metric.Failed);
        Assert.Null(metric.AnonymizedUserId);
        Assert.True(metric.DurationMilliseconds >= 0);
        Assert.Equal(0, store.ActiveRequests);
    }

    [Fact]
    public async Task InvokeAsync_ForAuthenticatedUser_StoresStableAnonymizedUserId()
    {
        const string userId = "11111111-2222-3333-4444-555555555555";
        const string anonymizationKey = "test-monitoring-key";

        var firstStore = CreateStore();
        var firstMiddleware = CreateMiddleware(
            _ => Task.CompletedTask,
            firstStore,
            enabled: true,
            anonymizationKey: anonymizationKey);
        var firstContext = new DefaultHttpContext();
        firstContext.User = CreateAuthenticatedUser(userId);

        await firstMiddleware.InvokeAsync(firstContext);

        var firstMetric = Assert.Single(firstStore.GetRecent());

        var secondStore = CreateStore();
        var secondMiddleware = CreateMiddleware(
            _ => Task.CompletedTask,
            secondStore,
            enabled: true,
            anonymizationKey: anonymizationKey);
        var secondContext = new DefaultHttpContext();
        secondContext.User = CreateAuthenticatedUser(userId);

        await secondMiddleware.InvokeAsync(secondContext);

        var secondMetric = Assert.Single(secondStore.GetRecent());

        Assert.NotNull(firstMetric.AnonymizedUserId);
        Assert.Equal(8, firstMetric.AnonymizedUserId.Length);
        Assert.Equal(
            firstMetric.AnonymizedUserId,
            secondMetric.AnonymizedUserId);
        Assert.DoesNotContain(
            userId,
            firstMetric.AnonymizedUserId,
            StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task InvokeAsync_ForUnauthenticatedUser_DoesNotStoreUserId()
    {
        var store = CreateStore();

        var middleware = CreateMiddleware(
            _ => Task.CompletedTask,
            store,
            enabled: true,
            anonymizationKey: "test-monitoring-key");

        await middleware.InvokeAsync(new DefaultHttpContext());

        var metric = Assert.Single(store.GetRecent());

        Assert.Null(metric.AnonymizedUserId);
    }

    [Fact]
    public async Task InvokeAsync_WhenEndpointIsUnmatched_DoesNotStoreRawPath()
    {
        var store = CreateStore();

        var middleware = CreateMiddleware(
            _ => Task.CompletedTask,
            store,
            enabled: true);

        var context = new DefaultHttpContext();
        context.Request.Path = "/private/path/with-sensitive-value";

        await middleware.InvokeAsync(context);

        var metric = Assert.Single(store.GetRecent());

        Assert.Equal("unmatched", metric.Route);
        Assert.DoesNotContain(
            "sensitive-value",
            metric.Route,
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task InvokeAsync_WhenRequestThrows_RecordsFailureAndRethrows()
    {
        var store = CreateStore();
        var expectedException =
            new InvalidOperationException("Synthetic test failure.");

        var middleware = CreateMiddleware(
            _ => throw expectedException,
            store,
            enabled: true);

        var context = new DefaultHttpContext();
        context.SetEndpoint(
            new RouteEndpoint(
                _ => Task.CompletedTask,
                RoutePatternFactory.Parse("/health"),
                order: 0,
                new EndpointMetadataCollection(),
                displayName: "Health"));

        var actualException = await Assert.ThrowsAsync<InvalidOperationException>(
            () => middleware.InvokeAsync(context));

        Assert.Same(expectedException, actualException);

        var metric = Assert.Single(store.GetRecent());

        Assert.Equal(StatusCodes.Status500InternalServerError, metric.StatusCode);
        Assert.True(metric.Failed);
        Assert.Equal("/health", metric.Route);
        Assert.Equal(0, store.ActiveRequests);
    }

    private static RequestMetricsMiddleware CreateMiddleware(
        RequestDelegate next,
        IRequestMetricsStore store,
        bool enabled,
        string anonymizationKey = "")
    {
        return new RequestMetricsMiddleware(
            next,
            store,
            Options.Create(
                new MonitoringOptions
                {
                    Enabled = enabled,
                    RequestCapacity = 100,
                    AnonymizationKey = anonymizationKey
                }));
    }

    private static ClaimsPrincipal CreateAuthenticatedUser(
        string userId)
    {
        var identity = new ClaimsIdentity(
            new[]
            {
                new Claim(
                    ClaimTypes.NameIdentifier,
                    userId)
            },
            authenticationType: "Test");

        return new ClaimsPrincipal(identity);
    }

    private static InMemoryRequestMetricsStore CreateStore()
    {
        return new InMemoryRequestMetricsStore(
            Options.Create(
                new MonitoringOptions
                {
                    RequestCapacity = 100
                }));
    }
}
