using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Npgsql;
using System.Net.Http.Headers;
using Fasty.Api.Modules.Identity;
using Fasty.Api.Modules.Identity.Tokens;
using Fasty.Api.Modules.Notes;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using Fasty.Api.Modules.Identity.Email;
using Fasty.Api.Modules.Identity.Google;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection.Extensions;
namespace Fasty.Api.Tests;

public sealed class FastyApiFactory : WebApplicationFactory<Program>
{
    private readonly TestAccountEmailSender _emailSender = new();

    private readonly TestGoogleAuthorizationCodeExchanger
        _googleAuthorizationCodeExchanger = new();

    internal TestGoogleAuthorizationCodeExchanger
        GoogleAuthorizationCodeExchanger =>
            _googleAuthorizationCodeExchanger;

    private const string TestIssuer = "Fasty.Tests";
    private const string TestAudience = "Fasty.Tests.Client";

    private const string TestSigningKey =
        "fasty-integration-tests-signing-key-2026-secure-value";
    public string ConnectionString { get; } =
        Environment.GetEnvironmentVariable("FASTY_TEST_DATABASE")
        ?? "Host=127.0.0.1;Port=5432;Database=fasty_tests;Username=postgres;Password=postgres";

    internal TestAccountEmailSender EmailSender =>
        _emailSender;

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");

        builder.ConfigureAppConfiguration((_, configuration) =>
        {
            configuration.AddInMemoryCollection(
                new Dictionary<string, string?>
                {
                    ["ConnectionStrings:FastyDatabase"] = ConnectionString,
                    ["Authentication:Tokens:Issuer"] = TestIssuer,
                    ["Authentication:Tokens:Audience"] = TestAudience,
                    ["Authentication:Tokens:SigningKey"] = TestSigningKey,
                    ["Authentication:Tokens:AccessTokenMinutes"] = "15",
                    ["Authentication:Tokens:RefreshTokenDays"] = "30",
                    ["Authentication:Registration:Enabled"] = "true",
                    ["Authentication:Google:Enabled"] = "true",
                    ["Authentication:Google:ClientIds:0"] =
                        "fasty-tests.apps.googleusercontent.com",
                    ["ReleaseAnnouncement:Enabled"] = "true",
                    ["ReleaseAnnouncement:Id"] = "private-beta-refresh-1",
                    ["ReleaseAnnouncement:Title"] = "Fasty beta update",
                    ["ReleaseAnnouncement:Message"] = "A new private beta build is available.",
                    ["ReleaseAnnouncement:ContactUrl"] = "mailto:christos@example.com",
                });
        });

        builder.ConfigureTestServices(services =>
        {
            services.AddSingleton<
                IAccountEmailSender>(
                _emailSender);

            services.RemoveAll<
                IGoogleIdentityTokenValidator>();

            services.AddSingleton<
                IGoogleIdentityTokenValidator,
                TestGoogleIdentityTokenValidator>();

            services.RemoveAll<
                IGoogleAuthorizationCodeExchanger>();

            services.AddSingleton<
                IGoogleAuthorizationCodeExchanger>(
                _googleAuthorizationCodeExchanger);
        });
    }

    public async Task ResetStorageAsync()
    {
        _emailSender.Reset();
        _googleAuthorizationCodeExchanger.Reset();

        // Creating a client forces Program startup, migrations, and workspace
        // storage initialization before the reset statements execute.
        _ = CreateClient();

        await using var connection = new NpgsqlConnection(ConnectionString);
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = """
    DELETE FROM analytics.archive_exports;
    DELETE FROM analytics.user_actions;
    TRUNCATE TABLE notes.notes;
    DELETE FROM notes.workspace_state;
    DELETE FROM auth.password_recovery_credentials;
    DELETE FROM auth.refresh_sessions;
    DELETE FROM auth.user_tokens;
    DELETE FROM auth.user_logins;
    DELETE FROM auth.user_claims;
    DELETE FROM auth.user_roles;
    DELETE FROM auth.users;
    """;
        await command.ExecuteNonQueryAsync();
    }
    public async Task<HttpClient> CreateAuthenticatedClientAsync(
    string email)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(email);

        var client = CreateClient();

        await using var scope =
            Services.CreateAsyncScope();

        var userManager =
            scope.ServiceProvider
                .GetRequiredService<UserManager<ApplicationUser>>();

        var accessTokenService =
            scope.ServiceProvider
                .GetRequiredService<IAccessTokenService>();

        var user = await userManager.FindByEmailAsync(email);

        if (user is null)
        {
            user = new ApplicationUser
            {
                Id = Guid.NewGuid(),
                UserName = email,
                Email = email,
                EmailConfirmed = true,
                CreatedAt = DateTimeOffset.UtcNow
            };

            var creationResult = await userManager.CreateAsync(user);

            if (!creationResult.Succeeded)
            {
                var errors = string.Join(
                    "; ",
                    creationResult.Errors.Select(
                        error => $"{error.Code}: {error.Description}"));

                client.Dispose();

                throw new InvalidOperationException(
                    $"Could not create integration-test user: {errors}");
            }
        }

        var token = accessTokenService.Generate(
            user,
            DateTimeOffset.UtcNow);

        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue(
                "Bearer",
                token.Token);

        return client;
    }

    public async Task ExecuteSqlAsync(
    string commandText,
    params NpgsqlParameter[] parameters)
    {
        await using var connection =
            new NpgsqlConnection(ConnectionString);

        await connection.OpenAsync();

        await using var command =
            connection.CreateCommand();

        command.CommandText = commandText;
        command.Parameters.AddRange(parameters);

        await command.ExecuteNonQueryAsync();
    }

    public async Task<T> ExecuteScalarAsync<T>(
        string commandText,
        params NpgsqlParameter[] parameters)
    {
        await using var connection =
            new NpgsqlConnection(ConnectionString);

        await connection.OpenAsync();

        await using var command =
            connection.CreateCommand();

        command.CommandText = commandText;
        command.Parameters.AddRange(parameters);

        var result = await command.ExecuteScalarAsync();

        if (result is null || result is DBNull)
        {
            throw new InvalidOperationException(
                "The scalar query returned no value.");
        }

        return (T)Convert.ChangeType(
            result,
            typeof(T));
    }
}
