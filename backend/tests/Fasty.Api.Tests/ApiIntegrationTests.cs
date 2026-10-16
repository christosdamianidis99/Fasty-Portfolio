using Microsoft.Extensions.Configuration;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Xunit;
namespace Fasty.Api.Tests;

public sealed class ApiIntegrationTests : IClassFixture<FastyApiFactory>
{
    private readonly FastyApiFactory _factory;

    public ApiIntegrationTests(FastyApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Health_and_readiness_report_available_database()
    {
        await _factory.ResetStorageAsync();
        using var client = _factory.CreateClient();

        var health = await client.GetAsync("/health");
        var readiness = await client.GetAsync("/health/ready");

        Assert.Equal(HttpStatusCode.OK, health.StatusCode);
        Assert.Equal(HttpStatusCode.OK, readiness.StatusCode);
        var readinessBody = await readiness.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("ready", readinessBody.GetProperty("status").GetString());
        Assert.Equal("reachable", readinessBody.GetProperty("database").GetString());
    }

    [Fact]
    public async Task Note_endpoint_keeps_the_newer_upsert()
    {
        await _factory.ResetStorageAsync();
        using var client =
    await _factory.CreateAuthenticatedClientAsync(
        "note-upsert@example.com");
        var id = Guid.NewGuid();
        var createdAt = DateTimeOffset.Parse("2026-07-25T10:00:00Z");

        var newer = new
        {
            title = "Newer title",
            content = "Newer content",
            createdAt,
            updatedAt = createdAt.AddMinutes(10)
        };
        var older = new
        {
            title = "Older title",
            content = "Older content",
            createdAt,
            updatedAt = createdAt.AddMinutes(5)
        };

        (await client.PutAsJsonAsync($"/api/v1/notes/{id}", newer))
            .EnsureSuccessStatusCode();
        (await client.PutAsJsonAsync($"/api/v1/notes/{id}", older))
            .EnsureSuccessStatusCode();

        var stored = await client.GetFromJsonAsync<JsonElement>(
            $"/api/v1/notes/{id}");
        Assert.Equal("Newer title", stored.GetProperty("title").GetString());
        Assert.Equal("Newer content", stored.GetProperty("content").GetString());
        Assert.False(stored.GetProperty("isDeleted").GetBoolean());
    }

    [Fact]
    public async Task Newer_delete_rejects_stale_restore_but_accepts_newer_restore()
    {
        await _factory.ResetStorageAsync();
        using var client =
    await _factory.CreateAuthenticatedClientAsync(
        "note-restore@example.com");
        var id = Guid.NewGuid();
        var createdAt = DateTimeOffset.Parse("2026-07-25T11:00:00Z");

        var original = new
        {
            title = "Original",
            content = "Original content",
            createdAt,
            updatedAt = createdAt
        };
        (await client.PutAsJsonAsync($"/api/v1/notes/{id}", original))
            .EnsureSuccessStatusCode();

        var deletedAt = createdAt.AddMinutes(10);
        var deleteUri = $"/api/v1/notes/{id}?updatedAt={Uri.EscapeDataString(deletedAt.ToString("O"))}";
        (await client.DeleteAsync(deleteUri)).EnsureSuccessStatusCode();

        var staleRestore = new
        {
            title = "Stale restore",
            content = "Must not win",
            createdAt,
            updatedAt = createdAt.AddMinutes(5)
        };
        (await client.PutAsJsonAsync($"/api/v1/notes/{id}", staleRestore))
            .EnsureSuccessStatusCode();

        var afterStaleRestore = await client.GetFromJsonAsync<JsonElement>(
            $"/api/v1/notes/{id}");
        Assert.True(afterStaleRestore.GetProperty("isDeleted").GetBoolean());
        Assert.Equal("Original", afterStaleRestore.GetProperty("title").GetString());

        var newerRestore = new
        {
            title = "Restored",
            content = "Newer restore wins",
            createdAt,
            updatedAt = createdAt.AddMinutes(11)
        };
        (await client.PutAsJsonAsync($"/api/v1/notes/{id}", newerRestore))
            .EnsureSuccessStatusCode();

        var restored = await client.GetFromJsonAsync<JsonElement>(
            $"/api/v1/notes/{id}");
        Assert.False(restored.GetProperty("isDeleted").GetBoolean());
        Assert.Equal("Restored", restored.GetProperty("title").GetString());
    }

    [Fact]
    public async Task Workspace_endpoint_keeps_the_newer_document()
    {
        await _factory.ResetStorageAsync();
        using var client =
    await _factory.CreateAuthenticatedClientAsync(
        "workspace-newer@example.com");
        var newerAt = DateTimeOffset.Parse("2026-07-25T12:10:00Z");
        var olderAt = DateTimeOffset.Parse("2026-07-25T12:05:00Z");

        var newer = WorkspaceDocument("newer-workspace", "Newer", newerAt);
        var older = WorkspaceDocument("older-workspace", "Older", olderAt);

        (await client.PutAsJsonAsync("/api/v1/workspace-state", newer))
            .EnsureSuccessStatusCode();
        (await client.PutAsJsonAsync("/api/v1/workspace-state", older))
            .EnsureSuccessStatusCode();

        var stored = await client.GetFromJsonAsync<JsonElement>(
            "/api/v1/workspace-state");
        Assert.Equal(
            "newer-workspace",
            stored.GetProperty("activeWorkspaceId").GetString());
        Assert.Equal(
            "Newer",
            stored.GetProperty("workspaces")[0].GetProperty("name").GetString());
    }

    [Fact]
    public async Task Workspace_endpoint_rejects_missing_update_timestamp()
    {
        await _factory.ResetStorageAsync();
        using var client =
    await _factory.CreateAuthenticatedClientAsync(
        "workspace-validation@example.com");

        var response = await client.PutAsJsonAsync(
            "/api/v1/workspace-state",
            new { schemaVersion = 1, workspaces = Array.Empty<object>() });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
    [Fact]
    public async Task Notes_endpoints_require_authentication()
    {
        await _factory.ResetStorageAsync();

        using var client = _factory.CreateClient();

        var response =
            await client.GetAsync("/api/v1/notes/");

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            response.StatusCode);
    }
    [Fact]
    public async Task Workspace_endpoints_require_authentication()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var response =
            await client.GetAsync(
                "/api/v1/workspace-state/");

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            response.StatusCode);
    }
    [Fact]
    public async Task Workspaces_are_isolated_between_users()
    {
        await _factory.ResetStorageAsync();

        using var firstClient =
            await _factory.CreateAuthenticatedClientAsync(
                "workspace-first@example.com");

        using var secondClient =
            await _factory.CreateAuthenticatedClientAsync(
                "workspace-second@example.com");

        var updatedAt =
            DateTimeOffset.Parse(
                "2026-07-27T14:00:00Z");

        var firstWorkspace =
            WorkspaceDocument(
                "first-private-workspace",
                "First user's workspace",
                updatedAt);

        using var saveResponse =
            await firstClient.PutAsJsonAsync(
                "/api/v1/workspace-state/",
                firstWorkspace);

        saveResponse.EnsureSuccessStatusCode();

        using var firstResponse =
            await firstClient.GetAsync(
                "/api/v1/workspace-state/");

        using var secondResponse =
            await secondClient.GetAsync(
                "/api/v1/workspace-state/");

        Assert.Equal(
            HttpStatusCode.OK,
            firstResponse.StatusCode);

        Assert.Equal(
            HttpStatusCode.NoContent,
            secondResponse.StatusCode);

        var stored =
            await firstResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.Equal(
            "first-private-workspace",
            stored.GetProperty(
                    "activeWorkspaceId")
                .GetString());
    }
    [Fact]
    public async Task Notes_are_isolated_between_users()
    {
        await _factory.ResetStorageAsync();

        using var firstClient =
            await _factory.CreateAuthenticatedClientAsync(
                "first-user@example.com");

        using var secondClient =
            await _factory.CreateAuthenticatedClientAsync(
                "second-user@example.com");

        var noteId = Guid.NewGuid();
        var createdAt =
            DateTimeOffset.Parse("2026-07-27T10:00:00Z");

        var note = new
        {
            title = "First user's private note",
            content = "Must not be visible to the second user",
            createdAt,
            updatedAt = createdAt
        };

        var createResponse =
            await firstClient.PutAsJsonAsync(
                $"/api/v1/notes/{noteId}",
                note);

        createResponse.EnsureSuccessStatusCode();

        var firstUserResponse =
            await firstClient.GetAsync(
                $"/api/v1/notes/{noteId}");

        var secondUserResponse =
            await secondClient.GetAsync(
                $"/api/v1/notes/{noteId}");

        Assert.Equal(
            HttpStatusCode.OK,
            firstUserResponse.StatusCode);

        Assert.Equal(
            HttpStatusCode.NotFound,
            secondUserResponse.StatusCode);

        var secondUserList =
            await secondClient.GetFromJsonAsync<JsonElement[]>(
                "/api/v1/notes/");

        Assert.NotNull(secondUserList);
        Assert.Empty(secondUserList);
    }

    [Fact]
    public async Task Registration_sends_confirmation_when_delivery_is_available()
    {
        await _factory.ResetStorageAsync();

        using var client = _factory.CreateClient();

        const string email =
            "registration-success@example.com";

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/register",
                new
                {
                    email,
                    password = "StrongPassword123!"
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            response.StatusCode);

        var sent =
            Assert.Single(
                _factory.EmailSender.Sent);

        Assert.Equal(
            email,
            sent.Email);

        Assert.False(
            string.IsNullOrWhiteSpace(
                sent.ConfirmationToken));

        var userCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.users
                """);

        Assert.Equal(
            1,
            userCount);
    }

    [Fact]
    public async Task Registration_does_not_create_user_when_delivery_is_unavailable()
    {
        await _factory.ResetStorageAsync();

        _factory.EmailSender.IsAvailable = false;

        using var client = _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/register",
                new
                {
                    email =
                        "registration-unavailable@example.com",
                    password = "StrongPassword123!"
                });

        Assert.Equal(
            HttpStatusCode.ServiceUnavailable,
            response.StatusCode);

        Assert.Empty(
            _factory.EmailSender.Sent);

        var userCount =
            await _factory.ExecuteScalarAsync<long>(
                """
                SELECT COUNT(*)
                FROM auth.users
                """);

        Assert.Equal(
            0,
            userCount);
    }

    [Fact]
    public async Task Resend_confirmation_sends_for_unconfirmed_user()
    {
        await _factory.ResetStorageAsync();

        using var client = _factory.CreateClient();

        const string email =
            "resend-unconfirmed@example.com";

        using var registrationResponse =
            await client.PostAsJsonAsync(
                "/api/auth/register",
                new
                {
                    email,
                    password = "StrongPassword123!"
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            registrationResponse.StatusCode);

        using var resendResponse =
            await client.PostAsJsonAsync(
                "/api/auth/resend-confirmation",
                new
                {
                    email
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            resendResponse.StatusCode);

        var sent =
            _factory.EmailSender.Sent.ToArray();

        Assert.Equal(
            2,
            sent.Length);

        Assert.All(
            sent,
            message =>
                Assert.Equal(
                    email,
                    message.Email));

        Assert.False(
            string.IsNullOrWhiteSpace(
                sent[1].ConfirmationToken));
    }

    [Fact]
    public async Task Resend_confirmation_uses_generic_response_for_unknown_user()
    {
        await _factory.ResetStorageAsync();

        using var client = _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/resend-confirmation",
                new
                {
                    email =
                        "resend-unknown@example.com"
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            response.StatusCode);

        var body =
            await response.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.Equal(
            "If the account requires confirmation, a verification message will be sent.",
            body.GetProperty("message").GetString());

        Assert.Empty(
            _factory.EmailSender.Sent);
    }

    [Fact]
    public async Task Resend_confirmation_does_not_send_for_confirmed_user()
    {
        await _factory.ResetStorageAsync();

        using var client = _factory.CreateClient();

        const string email =
            "resend-confirmed@example.com";

        using var registrationResponse =
            await client.PostAsJsonAsync(
                "/api/auth/register",
                new
                {
                    email,
                    password = "StrongPassword123!"
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            registrationResponse.StatusCode);

        var originalMessage =
            Assert.Single(
                _factory.EmailSender.Sent);

        using var confirmationResponse =
            await client.PostAsJsonAsync(
                "/api/auth/confirm-email",
                new
                {
                    email,
                    token =
                        originalMessage.ConfirmationToken
                });

        Assert.Equal(
            HttpStatusCode.OK,
            confirmationResponse.StatusCode);

        using var resendResponse =
            await client.PostAsJsonAsync(
                "/api/auth/resend-confirmation",
                new
                {
                    email
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            resendResponse.StatusCode);

        Assert.Single(
            _factory.EmailSender.Sent);
    }

    [Fact]
    public async Task Resend_confirmation_rejects_invalid_email()
    {
        await _factory.ResetStorageAsync();

        using var client = _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/resend-confirmation",
                new
                {
                    email = "invalid-email"
                });

        Assert.Equal(
            HttpStatusCode.BadRequest,
            response.StatusCode);

        Assert.Empty(
            _factory.EmailSender.Sent);
    }

    [Fact]
    public async Task Resend_confirmation_uses_generic_response_when_delivery_fails()
    {
        await _factory.ResetStorageAsync();

        using var client = _factory.CreateClient();

        const string email =
            "resend-failure@example.com";

        using var registrationResponse =
            await client.PostAsJsonAsync(
                "/api/auth/register",
                new
                {
                    email,
                    password = "StrongPassword123!"
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            registrationResponse.StatusCode);

        _factory.EmailSender.SendException =
            new InvalidOperationException(
                "Simulated provider failure.");

        using var resendResponse =
            await client.PostAsJsonAsync(
                "/api/auth/resend-confirmation",
                new
                {
                    email
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            resendResponse.StatusCode);

        var body =
            await resendResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.Equal(
            "If the account requires confirmation, a verification message will be sent.",
            body.GetProperty("message").GetString());

        Assert.Single(
            _factory.EmailSender.Sent);
    }
    [Fact]
    public async Task Resend_confirmation_is_unavailable_when_registration_is_disabled()
    {
        await _factory.ResetStorageAsync();

        using var disabledFactory =
            _factory.WithWebHostBuilder(
                builder =>
                {
                    builder.ConfigureAppConfiguration(
                        (_, configuration) =>
                        {
                            configuration.AddInMemoryCollection(
                                new Dictionary<string, string?>
                                {
                                    ["Authentication:Registration:Enabled"] =
                                        "false"
                                });
                        });
                });

        using var client =
            disabledFactory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/resend-confirmation",
                new
                {
                    email =
                        "registration-disabled@example.com"
                });

        Assert.Equal(
            HttpStatusCode.NotFound,
            response.StatusCode);

        Assert.Empty(
            _factory.EmailSender.Sent);
    }
    [Fact]
    public async Task Resend_confirmation_reports_unavailable_delivery()
    {
        await _factory.ResetStorageAsync();

        using var client = _factory.CreateClient();

        const string email =
            "resend-unavailable@example.com";

        using var registrationResponse =
            await client.PostAsJsonAsync(
                "/api/auth/register",
                new
                {
                    email,
                    password = "StrongPassword123!"
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            registrationResponse.StatusCode);

        _factory.EmailSender.IsAvailable = false;

        using var resendResponse =
            await client.PostAsJsonAsync(
                "/api/auth/resend-confirmation",
                new
                {
                    email
                });

        Assert.Equal(
            HttpStatusCode.ServiceUnavailable,
            resendResponse.StatusCode);

        Assert.Single(
            _factory.EmailSender.Sent);
    }
    [Fact]
    public async Task Forgot_password_sends_for_confirmed_user()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        const string email =
            "forgot-confirmed@example.com";

        await RegisterAndConfirmAsync(
            client,
            email,
            "StrongPassword123!");

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/forgot-password",
                new
                {
                    email
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            response.StatusCode);

        var reset =
            Assert.Single(
                _factory.EmailSender.PasswordResets);

        Assert.Equal(
            email,
            reset.Email);

        Assert.False(
            string.IsNullOrWhiteSpace(
                reset.PasswordResetToken));
    }

    [Fact]
    public async Task Forgot_password_uses_generic_response_for_unknown_and_unconfirmed_users()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var unknownResponse =
            await client.PostAsJsonAsync(
                "/api/auth/forgot-password",
                new
                {
                    email =
                        "forgot-unknown@example.com"
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            unknownResponse.StatusCode);

        var unknownBody =
            await unknownResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.Equal(
            "If the account can be recovered, a password reset message will be sent.",
            unknownBody.GetProperty("message").GetString());

        const string unconfirmedEmail =
            "forgot-unconfirmed@example.com";

        using var registrationResponse =
            await client.PostAsJsonAsync(
                "/api/auth/register",
                new
                {
                    email =
                        unconfirmedEmail,
                    password =
                        "StrongPassword123!"
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            registrationResponse.StatusCode);

        using var unconfirmedResponse =
            await client.PostAsJsonAsync(
                "/api/auth/forgot-password",
                new
                {
                    email =
                        unconfirmedEmail
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            unconfirmedResponse.StatusCode);

        var unconfirmedBody =
            await unconfirmedResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.Equal(
            unknownBody.GetProperty("message").GetString(),
            unconfirmedBody.GetProperty("message").GetString());

        Assert.Empty(
            _factory.EmailSender.PasswordResets);
    }

    [Fact]
    public async Task Forgot_password_rejects_invalid_email()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/forgot-password",
                new
                {
                    email = "invalid-email"
                });

        Assert.Equal(
            HttpStatusCode.BadRequest,
            response.StatusCode);

        Assert.Empty(
            _factory.EmailSender.PasswordResets);
    }

    [Fact]
    public async Task Forgot_password_hides_delivery_failure()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        const string email =
            "forgot-failure@example.com";

        await RegisterAndConfirmAsync(
            client,
            email,
            "StrongPassword123!");

        _factory.EmailSender.SendException =
            new InvalidOperationException(
                "Simulated password-reset provider failure.");

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/forgot-password",
                new
                {
                    email
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            response.StatusCode);

        var body =
            await response.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.Equal(
            "If the account can be recovered, a password reset message will be sent.",
            body.GetProperty("message").GetString());

        Assert.Empty(
            _factory.EmailSender.PasswordResets);
    }

    [Fact]
    public async Task Forgot_password_reports_unavailable_delivery()
    {
        await _factory.ResetStorageAsync();

        _factory.EmailSender.IsAvailable = false;

        using var client =
            _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/forgot-password",
                new
                {
                    email =
                        "forgot-unavailable@example.com"
                });

        Assert.Equal(
            HttpStatusCode.ServiceUnavailable,
            response.StatusCode);

        Assert.Empty(
            _factory.EmailSender.PasswordResets);
    }

    [Fact]
    public async Task Reset_password_replaces_old_password()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        const string email =
            "reset-success@example.com";

        const string oldPassword =
            "StrongPassword123!";

        const string newPassword =
            "Replacement456!";

        await RegisterAndConfirmAsync(
            client,
            email,
            oldPassword);

        using var initialLoginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password =
                        oldPassword,
                    deviceName =
                        "Pre-reset session"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            initialLoginResponse.StatusCode);

        var initialLoginBody =
            await initialLoginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var preResetRefreshToken =
            initialLoginBody
                .GetProperty("refreshToken")
                .GetString();

        Assert.False(
            string.IsNullOrWhiteSpace(
                preResetRefreshToken));

        using var forgotResponse =
            await client.PostAsJsonAsync(
                "/api/auth/forgot-password",
                new
                {
                    email
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            forgotResponse.StatusCode);

        var resetMessage =
            Assert.Single(
                _factory.EmailSender.PasswordResets);

        using var resetResponse =
            await client.PostAsJsonAsync(
                "/api/auth/reset-password",
                new
                {
                    email,
                    token =
                        resetMessage.PasswordResetToken,
                    newPassword
                });

        Assert.Equal(
            HttpStatusCode.OK,
            resetResponse.StatusCode);

        using var revokedRefreshResponse =
            await client.PostAsJsonAsync(
                "/api/auth/refresh",
                new
                {
                    refreshToken =
                        preResetRefreshToken
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            revokedRefreshResponse.StatusCode);

        using var oldLoginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password =
                        oldPassword,
                    deviceName =
                        "Password reset test"
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            oldLoginResponse.StatusCode);

        using var newLoginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password =
                        newPassword,
                    deviceName =
                        "Password reset test"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            newLoginResponse.StatusCode);
    }

    [Fact]
    public async Task Reset_password_rejects_invalid_token_and_weak_password()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        const string email =
            "reset-validation@example.com";

        await RegisterAndConfirmAsync(
            client,
            email,
            "StrongPassword123!");

        using var invalidTokenResponse =
            await client.PostAsJsonAsync(
                "/api/auth/reset-password",
                new
                {
                    email,
                    token =
                        "invalid-token",
                    newPassword =
                        "Replacement456!"
                });

        Assert.Equal(
            HttpStatusCode.BadRequest,
            invalidTokenResponse.StatusCode);

        var invalidTokenBody =
            await invalidTokenResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.Equal(
            "The password reset request is invalid or expired.",
            invalidTokenBody.GetProperty("message").GetString());

        using var forgotResponse =
            await client.PostAsJsonAsync(
                "/api/auth/forgot-password",
                new
                {
                    email
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            forgotResponse.StatusCode);

        var resetMessage =
            Assert.Single(
                _factory.EmailSender.PasswordResets);

        using var weakPasswordResponse =
            await client.PostAsJsonAsync(
                "/api/auth/reset-password",
                new
                {
                    email,
                    token =
                        resetMessage.PasswordResetToken,
                    newPassword =
                        "weak"
                });

        Assert.Equal(
            HttpStatusCode.BadRequest,
            weakPasswordResponse.StatusCode);

        var weakPasswordBody =
            await weakPasswordResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.True(
            weakPasswordBody.TryGetProperty(
                "errors",
                out _));
    }

    [Fact]
    public async Task Change_password_requires_authentication()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/change-password",
                new
                {
                    currentPassword =
                        "StrongPassword123!",
                    newPassword =
                        "Replacement456!"
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            response.StatusCode);
    }

    [Fact]
    public async Task Change_password_rejects_wrong_current_password()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        const string email =
            "change-wrong-current@example.com";

        const string password =
            "StrongPassword123!";

        await RegisterAndConfirmAsync(
            client,
            email,
            password);

        using var loginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password,
                    deviceName =
                        "Change password test"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            loginResponse.StatusCode);

        var loginBody =
            await loginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var accessToken =
            loginBody
                .GetProperty("accessToken")
                .GetString();

        Assert.False(
            string.IsNullOrWhiteSpace(accessToken));

        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue(
                "Bearer",
                accessToken);

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/change-password",
                new
                {
                    currentPassword =
                        "WrongPassword123!",
                    newPassword =
                        "Replacement456!"
                });

        Assert.Equal(
            HttpStatusCode.BadRequest,
            response.StatusCode);

        var body =
            await response.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.Equal(
            "The current password is incorrect.",
            body.GetProperty("message").GetString());
    }

    [Fact]
    public async Task Change_password_rejects_weak_new_password()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        const string email =
            "change-weak@example.com";

        const string password =
            "StrongPassword123!";

        await RegisterAndConfirmAsync(
            client,
            email,
            password);

        using var loginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password,
                    deviceName =
                        "Change password test"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            loginResponse.StatusCode);

        var loginBody =
            await loginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue(
                "Bearer",
                loginBody
                    .GetProperty("accessToken")
                    .GetString());

        using var response =
            await client.PostAsJsonAsync(
                "/api/auth/change-password",
                new
                {
                    currentPassword =
                        password,
                    newPassword =
                        "weak"
                });

        Assert.Equal(
            HttpStatusCode.BadRequest,
            response.StatusCode);

        var body =
            await response.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.True(
            body.TryGetProperty(
                "errors",
                out _));
    }

    [Fact]
    public async Task Change_password_replaces_password_and_revokes_sessions()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        const string email =
            "change-success@example.com";

        const string oldPassword =
            "StrongPassword123!";

        const string newPassword =
            "Replacement456!";

        await RegisterAndConfirmAsync(
            client,
            email,
            oldPassword);

        using var loginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password =
                        oldPassword,
                    deviceName =
                        "Pre-change session"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            loginResponse.StatusCode);

        var loginBody =
            await loginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var accessToken =
            loginBody
                .GetProperty("accessToken")
                .GetString();

        var refreshToken =
            loginBody
                .GetProperty("refreshToken")
                .GetString();

        Assert.False(
            string.IsNullOrWhiteSpace(accessToken));

        Assert.False(
            string.IsNullOrWhiteSpace(refreshToken));

        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue(
                "Bearer",
                accessToken);

        using var changeResponse =
            await client.PostAsJsonAsync(
                "/api/auth/change-password",
                new
                {
                    currentPassword =
                        oldPassword,
                    newPassword
                });

        Assert.Equal(
            HttpStatusCode.OK,
            changeResponse.StatusCode);

        client.DefaultRequestHeaders.Authorization =
            null;

        using var refreshResponse =
            await client.PostAsJsonAsync(
                "/api/auth/refresh",
                new
                {
                    refreshToken
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            refreshResponse.StatusCode);

        using var oldLoginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password =
                        oldPassword,
                    deviceName =
                        "Old password check"
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            oldLoginResponse.StatusCode);

        using var newLoginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password =
                        newPassword,
                    deviceName =
                        "New password check"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            newLoginResponse.StatusCode);
    }

    [Fact]
    public async Task Session_revocation_requires_authentication()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var response =
            await client.DeleteAsync(
                $"/api/auth/sessions/{Guid.NewGuid()}");

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            response.StatusCode);
    }

    [Fact]
    public async Task Session_revocation_invalidates_only_selected_session()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        const string email =
            "session-revocation@example.com";

        const string password =
            "StrongPassword123!";

        await RegisterAndConfirmAsync(
            client,
            email,
            password);

        using var firstLoginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password,
                    deviceName =
                        "Windows laptop"
                });

        firstLoginResponse
            .EnsureSuccessStatusCode();

        var firstBody =
            await firstLoginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var firstSessionId =
            firstBody
                .GetProperty("refreshSessionId")
                .GetGuid();

        var firstRefreshToken =
            firstBody
                .GetProperty("refreshToken")
                .GetString();

        using var secondLoginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password,
                    deviceName =
                        "Android phone"
                });

        secondLoginResponse
            .EnsureSuccessStatusCode();

        var secondBody =
            await secondLoginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var secondRefreshToken =
            secondBody
                .GetProperty("refreshToken")
                .GetString();

        var accessToken =
            secondBody
                .GetProperty("accessToken")
                .GetString();

        Assert.False(
            string.IsNullOrWhiteSpace(
                firstRefreshToken));

        Assert.False(
            string.IsNullOrWhiteSpace(
                secondRefreshToken));

        Assert.False(
            string.IsNullOrWhiteSpace(
                accessToken));

        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue(
                "Bearer",
                accessToken);

        using var revokeResponse =
            await client.DeleteAsync(
                $"/api/auth/sessions/{firstSessionId}");

        Assert.Equal(
            HttpStatusCode.NoContent,
            revokeResponse.StatusCode);

        client.DefaultRequestHeaders.Authorization =
            null;

        using var revokedRefreshResponse =
            await client.PostAsJsonAsync(
                "/api/auth/refresh",
                new
                {
                    refreshToken =
                        firstRefreshToken
                });

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            revokedRefreshResponse.StatusCode);

        using var activeRefreshResponse =
            await client.PostAsJsonAsync(
                "/api/auth/refresh",
                new
                {
                    refreshToken =
                        secondRefreshToken
                });

        Assert.Equal(
            HttpStatusCode.OK,
            activeRefreshResponse.StatusCode);
    }

    [Fact]
    public async Task Session_revocation_cannot_revoke_another_users_session()
    {
        await _factory.ResetStorageAsync();

        using var firstClient =
            _factory.CreateClient();

        const string firstEmail =
            "session-owner@example.com";

        const string secondEmail =
            "session-attacker@example.com";

        const string password =
            "StrongPassword123!";

        await RegisterAndConfirmAsync(
            firstClient,
            firstEmail,
            password);

        using var ownerLoginResponse =
            await firstClient.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email =
                        firstEmail,
                    password,
                    deviceName =
                        "Owner device"
                });

        ownerLoginResponse
            .EnsureSuccessStatusCode();

        var ownerBody =
            await ownerLoginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var ownerSessionId =
            ownerBody
                .GetProperty("refreshSessionId")
                .GetGuid();

        var ownerRefreshToken =
            ownerBody
                .GetProperty("refreshToken")
                .GetString();

        using var secondClient =
            _factory.CreateClient();

        await RegisterAndConfirmAsync(
            secondClient,
            secondEmail,
            password);

        using var attackerLoginResponse =
            await secondClient.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email =
                        secondEmail,
                    password,
                    deviceName =
                        "Attacker device"
                });

        attackerLoginResponse
            .EnsureSuccessStatusCode();

        var attackerBody =
            await attackerLoginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        secondClient.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue(
                "Bearer",
                attackerBody
                    .GetProperty("accessToken")
                    .GetString());

        using var revokeResponse =
            await secondClient.DeleteAsync(
                $"/api/auth/sessions/{ownerSessionId}");

        Assert.Equal(
            HttpStatusCode.NoContent,
            revokeResponse.StatusCode);

        firstClient.DefaultRequestHeaders.Authorization =
            null;

        using var ownerRefreshResponse =
            await firstClient.PostAsJsonAsync(
                "/api/auth/refresh",
                new
                {
                    refreshToken =
                        ownerRefreshToken
                });

        Assert.Equal(
            HttpStatusCode.OK,
            ownerRefreshResponse.StatusCode);
    }
    [Fact]
    public async Task Session_listing_requires_authentication()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        using var response =
            await client.GetAsync(
                "/api/auth/sessions");

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            response.StatusCode);
    }

    [Fact]
    public async Task Session_listing_returns_only_active_sessions_for_current_user()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        const string email =
            "session-listing@example.com";

        const string password =
            "StrongPassword123!";

        await RegisterAndConfirmAsync(
            client,
            email,
            password);

        using var firstLoginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password,
                    deviceName =
                        "Windows laptop"
                });

        firstLoginResponse
            .EnsureSuccessStatusCode();

        var firstLoginBody =
            await firstLoginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var firstSessionId =
            firstLoginBody
                .GetProperty("refreshSessionId")
                .GetGuid();

        var firstRefreshToken =
            firstLoginBody
                .GetProperty("refreshToken")
                .GetString();

        Assert.False(
            string.IsNullOrWhiteSpace(
                firstRefreshToken));

        using var secondLoginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password,
                    deviceName =
                        "Android phone"
                });

        secondLoginResponse
            .EnsureSuccessStatusCode();

        var secondLoginBody =
            await secondLoginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var secondSessionId =
            secondLoginBody
                .GetProperty("refreshSessionId")
                .GetGuid();

        var accessToken =
            secondLoginBody
                .GetProperty("accessToken")
                .GetString();

        Assert.False(
            string.IsNullOrWhiteSpace(
                accessToken));

        using var refreshResponse =
            await client.PostAsJsonAsync(
                "/api/auth/refresh",
                new
                {
                    refreshToken =
                        firstRefreshToken
                });

        refreshResponse
            .EnsureSuccessStatusCode();

        var refreshBody =
            await refreshResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var replacementSessionId =
            refreshBody
                .GetProperty("refreshSessionId")
                .GetGuid();

        using var otherClient =
            _factory.CreateClient();

        const string otherEmail =
            "other-session-listing@example.com";

        await RegisterAndConfirmAsync(
            otherClient,
            otherEmail,
            password);

        using var otherLoginResponse =
            await otherClient.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email =
                        otherEmail,
                    password,
                    deviceName =
                        "Other user's device"
                });

        otherLoginResponse
            .EnsureSuccessStatusCode();

        var otherLoginBody =
            await otherLoginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var otherSessionId =
            otherLoginBody
                .GetProperty("refreshSessionId")
                .GetGuid();

        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue(
                "Bearer",
                accessToken);

        using var response =
            await client.GetAsync(
                "/api/auth/sessions");

        response
            .EnsureSuccessStatusCode();

        var body =
            await response.Content
                .ReadFromJsonAsync<JsonElement>();

        Assert.Equal(
            JsonValueKind.Array,
            body.ValueKind);

        Assert.Equal(
            2,
            body.GetArrayLength());

        var sessionIds =
            body.EnumerateArray()
                .Select(
                    session =>
                        session
                            .GetProperty("id")
                            .GetGuid())
                .ToHashSet();

        Assert.Contains(
            secondSessionId,
            sessionIds);

        Assert.Contains(
            replacementSessionId,
            sessionIds);

        Assert.DoesNotContain(
            firstSessionId,
            sessionIds);

        Assert.DoesNotContain(
            otherSessionId,
            sessionIds);

        var deviceNames =
            body.EnumerateArray()
                .Select(
                    session =>
                        session
                            .GetProperty("deviceName")
                            .GetString())
                .ToHashSet();

        Assert.Contains(
            "Windows laptop",
            deviceNames);

        Assert.Contains(
            "Android phone",
            deviceNames);
    }
    [Fact]
    public async Task Login_and_refresh_return_refresh_session_ids()
    {
        await _factory.ResetStorageAsync();

        using var client =
            _factory.CreateClient();

        const string email =
            "session-id-response@example.com";

        const string password =
            "StrongPassword123!";

        await RegisterAndConfirmAsync(
            client,
            email,
            password);

        using var loginResponse =
            await client.PostAsJsonAsync(
                "/api/auth/login",
                new
                {
                    email,
                    password,
                    deviceName =
                        "Session ID test"
                });

        Assert.Equal(
            HttpStatusCode.OK,
            loginResponse.StatusCode);

        var loginBody =
            await loginResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var loginSessionId =
            loginBody
                .GetProperty("refreshSessionId")
                .GetGuid();

        var refreshToken =
            loginBody
                .GetProperty("refreshToken")
                .GetString();

        Assert.NotEqual(
            Guid.Empty,
            loginSessionId);

        Assert.False(
            string.IsNullOrWhiteSpace(
                refreshToken));

        using var refreshResponse =
            await client.PostAsJsonAsync(
                "/api/auth/refresh",
                new
                {
                    refreshToken
                });

        Assert.Equal(
            HttpStatusCode.OK,
            refreshResponse.StatusCode);

        var refreshBody =
            await refreshResponse.Content
                .ReadFromJsonAsync<JsonElement>();

        var replacementSessionId =
            refreshBody
                .GetProperty("refreshSessionId")
                .GetGuid();

        Assert.NotEqual(
            Guid.Empty,
            replacementSessionId);

        Assert.NotEqual(
            loginSessionId,
            replacementSessionId);
    }
    private async Task RegisterAndConfirmAsync(
        HttpClient client,
        string email,
        string password)
    {
        using var registrationResponse =
            await client.PostAsJsonAsync(
                "/api/auth/register",
                new
                {
                    email,
                    password
                });

        Assert.Equal(
            HttpStatusCode.Accepted,
            registrationResponse.StatusCode);

        var confirmation =
            _factory.EmailSender.Sent
                .Last(
                    sent =>
                        string.Equals(
                            sent.Email,
                            email,
                            StringComparison.OrdinalIgnoreCase));

        using var confirmationResponse =
            await client.PostAsJsonAsync(
                "/api/auth/confirm-email",
                new
                {
                    email,
                    token =
                        confirmation.ConfirmationToken
                });

        Assert.Equal(
            HttpStatusCode.OK,
            confirmationResponse.StatusCode);
    }
    private static object WorkspaceDocument(
        string id,
        string name,
        DateTimeOffset updatedAt)
    {
        return new
        {
            schemaVersion = 1,
            activeWorkspaceId = id,
            workspaces = new[]
            {
                new
                {
                    id,
                    name,
                    colorValue = 0xFF625BEB,
                    cameraX = 0,
                    cameraY = 0,
                    scale = 1,
                    createdAt = updatedAt,
                    updatedAt
                }
            },
            placements = Array.Empty<object>(),
            links = Array.Empty<object>(),
            updatedAt
        };
    }

}
