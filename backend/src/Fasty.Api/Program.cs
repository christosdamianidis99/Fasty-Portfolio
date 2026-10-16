using Fasty.Api.Modules.Monitoring;
using Fasty.Api.Modules.Notes;
using Fasty.Api.Modules.Workspaces;
using Fasty.Api.Modules.Releases;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Fasty.Api.Modules.Identity.Tokens;
using System.Text;
using Fasty.Api.Modules.Identity;
using Fasty.Api.Modules.Identity.Google;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using JwtTokenOptions = Fasty.Api.Modules.Identity.Tokens.TokenOptions;
using Fasty.Api.Modules.Identity.Email;

var builder = WebApplication.CreateBuilder(args);
var configuredOrigins = builder.Configuration
    .GetSection("Cors:AllowedOrigins")
    .Get<string[]>()
    ?? [];
var registrationRequiresEmailVerification =
    builder.Configuration.GetValue<bool?>(
        $"{RegistrationOptions.SectionName}:RequireEmailVerification")
    ?? true;

builder.Services.AddOpenApi();
builder.Services
    .AddOptions<MonitoringOptions>()
    .Bind(
        builder.Configuration.GetSection(
            MonitoringOptions.SectionName))
    .Validate(
        options => options.RequestCapacity > 0,
        "Monitoring request capacity must be greater than zero.")
    .Validate(
        options => options.RetentionDays > 0,
        "Monitoring retention days must be greater than zero.")
    .ValidateOnStart();
builder.Services.AddSingleton<
    IRequestMetricsStore,
    InMemoryRequestMetricsStore>();

builder.Services.AddSingleton<
    IUserActionStore,
    PersistentUserActionStore>();

builder.Services.AddSingleton<
    IUserActionTracker,
    UserActionTracker>();

builder.Services.AddSingleton<
    AnalyticsSnapshotImporter>();

builder.Services.AddSingleton<
    AnalyticsArchivePlanner>();

builder.Services.AddSingleton<
    AnalyticsArchiveExporter>();

builder.Services.AddSingleton<
    AnalyticsArchiveMetadataStore>();

builder.Services.AddCors(options =>
{
    options.AddPolicy("ClientApps", policy =>
        policy
            .SetIsOriginAllowed(origin =>
            {
                if (!Uri.TryCreate(origin, UriKind.Absolute, out var uri))
                {
                    return false;
                }

                var isLocalFlutterClient =
                    uri.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase)
                    || uri.Host.Equals("127.0.0.1", StringComparison.OrdinalIgnoreCase);

                var isConfiguredClient = configuredOrigins.Any(allowedOrigin =>
                    string.Equals(
                        allowedOrigin.TrimEnd('/'),
                        origin.TrimEnd('/'),
                        StringComparison.OrdinalIgnoreCase));

                return isLocalFlutterClient || isConfiguredClient;
            })
            .AllowAnyHeader()
            .AllowAnyMethod());
});
builder.Services.AddDbContext<NotesDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("FastyDatabase")));

builder.Services
    .AddIdentityCore<ApplicationUser>(options =>
    {
        options.User.RequireUniqueEmail = true;

        options.SignIn.RequireConfirmedEmail =
            registrationRequiresEmailVerification;

        options.Password.RequiredLength = 12;
        options.Password.RequiredUniqueChars = 4;
        options.Password.RequireUppercase = true;
        options.Password.RequireLowercase = true;
        options.Password.RequireDigit = true;
        options.Password.RequireNonAlphanumeric = true;

        options.Lockout.AllowedForNewUsers = true;
        options.Lockout.MaxFailedAccessAttempts = 5;
        options.Lockout.DefaultLockoutTimeSpan =
            TimeSpan.FromMinutes(15);
    })
.AddRoles<IdentityRole<Guid>>()
.AddEntityFrameworkStores<NotesDbContext>()
.AddUserManager<RegistrationUserManager>()
.AddSignInManager()
.AddDefaultTokenProviders();


builder.Services
    .AddOptions<GoogleAuthOptions>()
    .Bind(
        builder.Configuration.GetSection(
            GoogleAuthOptions.SectionName))
    .Validate(
        options =>
            !options.Enabled
            || options.ClientIds.Any(
                clientId =>
                    !string.IsNullOrWhiteSpace(
                        clientId)),
        "At least one Google client ID is required when Google authentication is enabled.")
    .ValidateOnStart();

builder.Services.AddSingleton<
    IGoogleIdentityTokenValidator,
    GoogleIdentityTokenValidator>();

builder.Services
    .AddHttpClient<
        IGoogleAuthorizationCodeExchanger,
        GoogleAuthorizationCodeExchanger>(
        client =>
        {
            client.BaseAddress =
                new Uri(
                    "https://oauth2.googleapis.com/");
        });

builder.Services
    .AddOptions<JwtTokenOptions>()
    .Bind(builder.Configuration.GetSection(JwtTokenOptions.SectionName))
    .Validate(
        options => !string.IsNullOrWhiteSpace(options.Issuer),
        "Token issuer is required.")
    .Validate(
        options => !string.IsNullOrWhiteSpace(options.Audience),
        "Token audience is required.")
    .Validate(
        options => !string.IsNullOrWhiteSpace(options.SigningKey),
        "Token signing key is required.")
    .ValidateOnStart();
builder.Services
.AddOptions<OwnerBootstrapOptions>()
.Bind(
    builder.Configuration.GetSection(
        OwnerBootstrapOptions.SectionName));
builder.Services
    .AddOptions<RecoveryAdminOptions>()
    .Bind(
        builder.Configuration.GetSection(
            RecoveryAdminOptions.SectionName))
    .Validate(
        options =>
            !options.Enabled
            || !string.IsNullOrWhiteSpace(options.Secret),
        "Recovery admin secret is required when recovery administration is enabled.")
    .Validate(
        options =>
            !options.Enabled
            || options.Secret.Length >= 32,
        "Recovery admin secret must contain at least 32 characters.")
    .Validate(
        options =>
            options.CredentialLifetimeMinutes > 0
            && options.CredentialLifetimeMinutes <= 120,
        "Recovery credential lifetime must be between 1 and 120 minutes.")
    .ValidateOnStart();
builder.Services.AddSingleton<IRefreshTokenGenerator, RefreshTokenGenerator>();
builder.Services
    .AddOptions<RegistrationOptions>()
    .Bind(
        builder.Configuration.GetSection(
            RegistrationOptions.SectionName));
builder.Services
    .AddOptions<ReleaseAnnouncementOptions>()
    .Bind(
        builder.Configuration.GetSection(
            ReleaseAnnouncementOptions.SectionName));
builder.Services.AddSingleton<
    IAccessTokenService,
    AccessTokenService>();

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer();

builder.Services
    .AddOptions<JwtBearerOptions>(
        JwtBearerDefaults.AuthenticationScheme)
    .Configure<IOptions<JwtTokenOptions>>(
        (jwtOptions, tokenOptionsAccessor) =>
        {
            var tokenOptions = tokenOptionsAccessor.Value;

            jwtOptions.MapInboundClaims = false;

            jwtOptions.TokenValidationParameters =
                new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = tokenOptions.Issuer,

                    ValidateAudience = true,
                    ValidAudience = tokenOptions.Audience,

                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = new SymmetricSecurityKey(
                        Encoding.UTF8.GetBytes(
                            tokenOptions.SigningKey)),

                    ValidateLifetime = true,
                    RequireExpirationTime = true,
                    RequireSignedTokens = true,
                    ClockSkew = TimeSpan.FromSeconds(30),
                    NameClaimType = "sub"
                };
        });

builder.Services.AddSingleton<
    IValidateOptions<EmailDeliveryOptions>,
    EmailDeliveryOptionsValidator>();

builder.Services
    .AddOptions<EmailDeliveryOptions>()
    .Bind(
        builder.Configuration.GetSection(
            EmailDeliveryOptions.SectionName))
    .ValidateOnStart();

builder.Services
    .AddOptions<ResendOptions>()
    .Bind(
        builder.Configuration.GetSection(
            ResendOptions.SectionName));

builder.Services
    .AddOptions<SmtpOptions>()
    .Bind(
        builder.Configuration.GetSection(
            SmtpOptions.SectionName));

builder.Services.AddAuthorization();

var emailDeliveryEnabled =
    builder.Configuration.GetValue<bool>(
        $"{EmailDeliveryOptions.SectionName}:Enabled");

var emailProvider =
    builder.Configuration.GetValue<string>(
        $"{EmailDeliveryOptions.SectionName}:Provider")
    ?? EmailProviderNames.Resend;

if (builder.Environment.IsDevelopment())
{
    builder.Services.AddSingleton<
        IAccountEmailSender,
        DevelopmentAccountEmailSender>();
}
else if (!emailDeliveryEnabled
    && !registrationRequiresEmailVerification)
{
    builder.Services.AddSingleton<
        IAccountEmailSender,
        BetaAccountEmailSender>();
}
else if (!emailDeliveryEnabled)
{
    builder.Services.AddSingleton<
        IAccountEmailSender,
        UnavailableAccountEmailSender>();
}
else if (
    string.Equals(
        emailProvider,
        EmailProviderNames.Smtp,
        StringComparison.OrdinalIgnoreCase))
{
    builder.Services.AddSingleton<
        IValidateOptions<SmtpOptions>,
        SmtpOptionsValidator>();

    builder.Services
        .AddOptions<SmtpOptions>()
        .ValidateOnStart();

    builder.Services.AddSingleton<
        ISmtpEmailTransport,
        MailKitSmtpEmailTransport>();

    builder.Services.AddSingleton<
        IAccountEmailSender,
        SmtpAccountEmailSender>();
}
else if (
    string.Equals(
        emailProvider,
        EmailProviderNames.Resend,
        StringComparison.OrdinalIgnoreCase))
{
    builder.Services.AddSingleton<
        IValidateOptions<ResendOptions>,
        ResendOptionsValidator>();

    builder.Services
        .AddOptions<ResendOptions>()
        .ValidateOnStart();

    builder.Services
        .AddHttpClient<
            IAccountEmailSender,
            ResendAccountEmailSender>(
            client =>
            {
                client.BaseAddress =
                    new Uri(
                        "https://api.resend.com/");
            });
}
else
{
    builder.Services.AddSingleton<
        IAccountEmailSender,
        UnavailableAccountEmailSender>();
}

var app = builder.Build();

app.MapOpenApi();

// Flutter web requires CORS in both local dotnet runs and production-mode
// containers. The policy remains restricted to localhost and explicitly
// configured client origins instead of allowing every website.
app.UseCors("ClientApps");
app.UseAuthentication();
app.UseAuthorization();
app.UseMiddleware<RequestMetricsMiddleware>();
app.MapGet("/health", () => Results.Ok(new
{
    status = "healthy",
    service = "Fasty.Api",
    utcTime = DateTimeOffset.UtcNow
}));

app.MapGet("/health/ready", async (IConfiguration configuration, CancellationToken cancellationToken) =>
{
    var connectionString = configuration.GetConnectionString("FastyDatabase");
    if (string.IsNullOrWhiteSpace(connectionString))
    {
        return Results.Problem("Database connection string is not configured.", statusCode: 503);
    }

    try
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand("SELECT 1", connection);
        await command.ExecuteScalarAsync(cancellationToken);
        return Results.Ok(new { status = "ready", database = "reachable" });
    }
    catch (Exception exception)
    {
        app.Logger.LogError(exception, "Database readiness check failed.");
        return Results.Problem("Database is not reachable.", statusCode: 503);
    }
});

app.MapIdentityEndpoints();
app.MapNotesEndpoints();
app.MapWorkspaceStateEndpoints();
app.MapMonitoringEndpoints();
app.MapUserAnalyticsEndpoints();
app.MapReleaseAnnouncementEndpoints();

await ApplyDatabaseMigrationsAsync(app);
await WorkspaceStateEndpoints.EnsureStorageAsync(
    app.Configuration);
await AnalyticsStorage.EnsureStorageAsync(
    app.Configuration);

await app.Services
    .GetRequiredService<AnalyticsSnapshotImporter>()
    .ImportConfiguredSnapshotAsync();

await app.Services
    .GetRequiredService<AnalyticsArchivePlanner>()
    .PlanAsync();

await app.RunAsync();

static async Task ApplyDatabaseMigrationsAsync(WebApplication app)
{
    await using var scope = app.Services.CreateAsyncScope();

    var dbContext =
        scope.ServiceProvider.GetRequiredService<NotesDbContext>();

    await dbContext.Database.MigrateAsync();
}

public partial class Program;
