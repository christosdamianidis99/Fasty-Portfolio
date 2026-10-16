using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Xunit;

namespace Fasty.Api.Tests;

public sealed class ReleaseAnnouncementIntegrationTests
    : IClassFixture<FastyApiFactory>
{
    private readonly FastyApiFactory _factory;

    public ReleaseAnnouncementIntegrationTests(FastyApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Active_release_announcement_is_available_without_authentication()
    {
        using var client = _factory.CreateClient();

        var response =
            await client.GetAsync("/api/v1/release-announcement");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body =
            await response.Content.ReadFromJsonAsync<JsonElement>();

        Assert.Equal(
            "private-beta-refresh-1",
            body.GetProperty("id").GetString());

        Assert.Equal(
            "Fasty beta update",
            body.GetProperty("title").GetString());

        Assert.Equal(
            "A new private beta build is available.",
            body.GetProperty("message").GetString());

        Assert.Equal(
            "mailto:christos@example.com",
            body.GetProperty("contactUrl").GetString());
    }

    [Fact]
    public async Task Disabled_release_announcement_returns_no_content()
    {
        using var disabledFactory =
            _factory.WithWebHostBuilder(builder =>
            {
                builder.ConfigureAppConfiguration(
                    (_, configuration) =>
                    {
                        configuration.AddInMemoryCollection(
                            new Dictionary<string, string?>
                            {
                                ["ReleaseAnnouncement:Enabled"] = "false"
                            });
                    });
            });

        using var client = disabledFactory.CreateClient();

        var response =
            await client.GetAsync("/api/v1/release-announcement");

        Assert.Equal(
            HttpStatusCode.NoContent,
            response.StatusCode);
    }

    [Fact]
    public async Task Incomplete_release_announcement_returns_no_content()
    {
        using var incompleteFactory =
            _factory.WithWebHostBuilder(builder =>
            {
                builder.ConfigureAppConfiguration(
                    (_, configuration) =>
                    {
                        configuration.AddInMemoryCollection(
                            new Dictionary<string, string?>
                            {
                                ["ReleaseAnnouncement:Enabled"] = "true",
                                ["ReleaseAnnouncement:Id"] = ""
                            });
                    });
            });

        using var client = incompleteFactory.CreateClient();

        var response =
            await client.GetAsync("/api/v1/release-announcement");

        Assert.Equal(
            HttpStatusCode.NoContent,
            response.StatusCode);
    }
}
