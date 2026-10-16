using System.Net;

namespace Fasty.Api.Tests.Identity;

internal sealed class CapturingHttpMessageHandler
    : HttpMessageHandler
{
    private readonly HttpStatusCode _statusCode;
    private readonly string _responseBody;

    public CapturingHttpMessageHandler(
        HttpStatusCode statusCode =
            HttpStatusCode.OK,
        string responseBody =
            """{"id":"test-email-id"}""")
    {
        _statusCode = statusCode;
        _responseBody = responseBody;
    }

    public HttpRequestMessage? Request { get; private set; }

    public string? RequestBody { get; private set; }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        Request = request;

        RequestBody =
            request.Content is null
                ? null
                : await request.Content.ReadAsStringAsync(
                    cancellationToken);

        return new HttpResponseMessage(
            _statusCode)
        {
            Content =
                new StringContent(
                    _responseBody)
        };
    }
}
