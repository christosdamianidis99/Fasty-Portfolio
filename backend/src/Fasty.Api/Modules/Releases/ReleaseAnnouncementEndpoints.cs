using Microsoft.Extensions.Options;

namespace Fasty.Api.Modules.Releases;

public static class ReleaseAnnouncementEndpoints
{
    public static IEndpointRouteBuilder MapReleaseAnnouncementEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        endpoints
            .MapGet(
                "/api/v1/release-announcement",
                (IOptions<ReleaseAnnouncementOptions> optionsAccessor) =>
                {
                    var options = optionsAccessor.Value;

                    if (!options.Enabled
                        || string.IsNullOrWhiteSpace(options.Id)
                        || string.IsNullOrWhiteSpace(options.Title)
                        || string.IsNullOrWhiteSpace(options.Message))
                    {
                        return Results.NoContent();
                    }

                    var contactUrl = string.IsNullOrWhiteSpace(options.ContactUrl)
                        ? null
                        : options.ContactUrl.Trim();

                    return Results.Ok(
                        new
                        {
                            id = options.Id.Trim(),
                            title = options.Title.Trim(),
                            message = options.Message.Trim(),
                            contactUrl
                        });
                })
            .AllowAnonymous();

        return endpoints;
    }
}
