using System.Data;
using System.Security.Claims;
using System.Text;
using Fasty.Api.Modules.Identity.Contracts;
using Fasty.Api.Modules.Identity.Email;
using Fasty.Api.Modules.Identity.Google;
using Fasty.Api.Modules.Identity.Tokens;
using Fasty.Api.Modules.Monitoring;
using Fasty.Api.Modules.Notes;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using JwtTokenOptions =
    Fasty.Api.Modules.Identity.Tokens.TokenOptions;

namespace Fasty.Api.Modules.Identity;

public static class IdentityEndpoints
{
    private const string GenericRegistrationMessage =
        "If this email can be registered, a verification message will be sent.";

    private const string GenericResendConfirmationMessage =
        "If the account requires confirmation, a verification message will be sent.";

    private const string GenericForgotPasswordMessage =
        "If the account can be recovered, a password reset message will be sent.";
    public static IEndpointRouteBuilder MapIdentityEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints
            .MapGroup("/api/auth")
            .WithTags("Authentication");

        group.MapPost(
                "/register",
                RegisterAsync)
            .AllowAnonymous();


        group.MapPost("/login", LoginAsync)
            .AllowAnonymous();

        group.MapPost(
                "/google",
                GoogleLoginAsync)
            .AllowAnonymous();

        group.MapPost(
                "/google/desktop/exchange",
                ExchangeDesktopGoogleCodeAsync)
            .AllowAnonymous();

        group.MapPost("/logout", LogoutAsync)
            .AllowAnonymous();

        group.MapPost("/refresh", RefreshAsync)
            .AllowAnonymous();

        group.MapPost(
                "/confirm-email",
                ConfirmEmailAsync)
            .AllowAnonymous();

        group.MapPost(
                "/resend-confirmation",
                ResendConfirmationAsync)
            .AllowAnonymous();

        group.MapPost(
                "/forgot-password",
                ForgotPasswordAsync)
            .AllowAnonymous();

        group.MapPost(
                "/reset-password",
                ResetPasswordAsync)
            .AllowAnonymous();

        group.MapPost(
                "/admin/password-recovery-credentials",
                IssuePasswordRecoveryCredentialAsync)
            .AllowAnonymous();

        group.MapPost(
                "/password-recovery/redeem",
                RedeemPasswordRecoveryCredentialAsync)
            .AllowAnonymous();

        group.MapPost(
                "/change-password",
                ChangePasswordAsync)
            .RequireAuthorization();

        group.MapPost(
                "/google/link",
                LinkGoogleAsync)
            .RequireAuthorization();

        group.MapGet(
                "/google/link",
                GetGoogleLinkStatusAsync)
            .RequireAuthorization();

        group.MapGet(
                "/sessions",
                ListSessionsAsync)
            .RequireAuthorization();

        group.MapDelete(
                "/sessions/{sessionId:guid}",
                RevokeSessionAsync)
            .RequireAuthorization();

        return endpoints;
    }

    private static async Task<IResult> RevokeSessionAsync(
        Guid sessionId,
        HttpContext httpContext,
        NotesDbContext dbContext,
        IUserActionTracker actionTracker,
        CancellationToken cancellationToken)
    {
        var userIdValue =
            httpContext.User.FindFirstValue(
                ClaimTypes.NameIdentifier);

        if (!Guid.TryParse(
                userIdValue,
                out var userId))
        {
            return Results.Unauthorized();
        }

        await using var transaction =
            await dbContext.Database.BeginTransactionAsync(
                IsolationLevel.ReadCommitted,
                cancellationToken);

        var session =
            await dbContext.RefreshSessions
                .FromSqlInterpolated(
                    $"""
                    SELECT *
                    FROM auth.refresh_sessions
                    WHERE "Id" = {sessionId}
                      AND "UserId" = {userId}
                    FOR UPDATE
                    """)
                .SingleOrDefaultAsync(
                    cancellationToken);

        if (session is null)
        {
            await transaction.RollbackAsync(
                cancellationToken);

            return Results.NoContent();
        }

        session.Revoke(
            DateTimeOffset.UtcNow);

        await dbContext.SaveChangesAsync(
            cancellationToken);

        await transaction.CommitAsync(
            cancellationToken);

        await actionTracker.TrackAsync(
            userId,
            UserActionTypes.SessionRevoked);

        return Results.NoContent();
    }
    private static async Task<IResult> ListSessionsAsync(
        HttpContext httpContext,
        NotesDbContext dbContext,
        CancellationToken cancellationToken)
    {
        var userIdValue =
            httpContext.User.FindFirstValue(
                ClaimTypes.NameIdentifier);

        if (!Guid.TryParse(
                userIdValue,
                out var userId))
        {
            return Results.Unauthorized();
        }

        var utcNow =
            DateTimeOffset.UtcNow;

        var sessions =
            await dbContext.RefreshSessions
                .AsNoTracking()
                .Where(
                    session =>
                        session.UserId == userId
                        && session.RevokedAt == null
                        && session.ExpiresAt > utcNow)
                .OrderByDescending(
                    session =>
                        session.LastUsedAt
                        ?? session.CreatedAt)
                .ThenByDescending(
                    session =>
                        session.CreatedAt)
                .Select(
                    session =>
                        new RefreshSessionResponse(
                            session.Id,
                            session.DeviceName,
                            session.CreatedAt,
                            session.LastUsedAt,
                            session.ExpiresAt))
                .ToListAsync(
                    cancellationToken);

        return Results.Ok(
            sessions);
    }
    private static async Task<IResult> RegisterAsync(
        RegisterRequest request,
        UserManager<ApplicationUser> userManager,
        IAccountEmailSender emailVerificationSender,
        IOptions<RegistrationOptions> registrationOptionsAccessor,
        IUserActionTracker actionTracker,
        CancellationToken cancellationToken)
    {
        var registrationOptions =
            registrationOptionsAccessor.Value;

        if (!registrationOptions.Enabled)
        {
            return Results.NotFound();
        }

        if (!emailVerificationSender.IsAvailable)
        {
            return Results.Problem(
                title: "Email verification unavailable",
                detail:
                    "Registration is temporarily unavailable.",
                statusCode:
                    StatusCodes.Status503ServiceUnavailable);
        }

        var email = request.Email?.Trim();

        if (string.IsNullOrWhiteSpace(email)
            || string.IsNullOrWhiteSpace(request.Password))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["registration"] =
                    [
                        "A valid email address and password are required."
                    ]
                });
        }

        var existingUser =
            await userManager.FindByEmailAsync(email);

        if (existingUser is not null)
        {
            return Results.Accepted(
                value: new RegistrationResponse(
                    GenericRegistrationMessage));
        }

        var user = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            UserName = email,
            Email = email,
            CreatedAt = DateTimeOffset.UtcNow
        };

        var creationResult =
            await userManager.CreateAsync(
                user,
                request.Password);

        if (!creationResult.Succeeded)
        {
            var errors = creationResult.Errors
                .GroupBy(error => error.Code)
                .ToDictionary(
                    group => group.Key,
                    group => group
                        .Select(error => error.Description)
                        .ToArray());

            return Results.ValidationProblem(errors);
        }

        await SendEmailConfirmationAsync(
            user,
            email,
            userManager,
            emailVerificationSender,
            cancellationToken);

        await actionTracker.TrackAsync(
            user.Id,
            UserActionTypes.UserRegistered);

        return Results.Accepted(
            value: new RegistrationResponse(
                GenericRegistrationMessage));
    }

    private static async Task<IResult> ResendConfirmationAsync(
        ResendConfirmationRequest request,
        UserManager<ApplicationUser> userManager,
        IAccountEmailSender emailVerificationSender,
        IOptions<RegistrationOptions> registrationOptionsAccessor,
        ILoggerFactory loggerFactory,
        CancellationToken cancellationToken)
    {
        var registrationOptions =
            registrationOptionsAccessor.Value;

        if (!registrationOptions.Enabled)
        {
            return Results.NotFound();
        }

        if (!emailVerificationSender.IsAvailable)
        {
            return Results.Problem(
                title: "Email verification unavailable",
                detail:
                    "Email confirmation is temporarily unavailable.",
                statusCode:
                    StatusCodes.Status503ServiceUnavailable);
        }

        var email = request.Email?.Trim();

        if (string.IsNullOrWhiteSpace(email)
            || !email.Contains(
                '@',
                StringComparison.Ordinal))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["confirmation"] =
                    [
                        "A valid email address is required."
                    ]
                });
        }

        var user =
            await userManager.FindByEmailAsync(email);

        if (user is null
            || await userManager.IsEmailConfirmedAsync(user))
        {
            return Results.Accepted(
                value: new RegistrationResponse(
                    GenericResendConfirmationMessage));
        }

        try
        {
            await SendEmailConfirmationAsync(
                user,
                email,
                userManager,
                emailVerificationSender,
                cancellationToken);
        }
        catch (OperationCanceledException)
            when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            var logger =
                loggerFactory.CreateLogger(
                    typeof(IdentityEndpoints).FullName!);

            logger.LogWarning(
                exception,
                "Could not resend an email confirmation message.");
        }

        return Results.Accepted(
            value: new RegistrationResponse(
                GenericResendConfirmationMessage));
    }

    private static async Task<IResult> ForgotPasswordAsync(
        ForgotPasswordRequest request,
        UserManager<ApplicationUser> userManager,
        IAccountEmailSender accountEmailSender,
        ILoggerFactory loggerFactory,
        CancellationToken cancellationToken)
    {
        if (!accountEmailSender.IsAvailable)
        {
            return Results.Problem(
                title: "Password recovery unavailable",
                detail:
                    "Password recovery is temporarily unavailable.",
                statusCode:
                    StatusCodes.Status503ServiceUnavailable);
        }

        var email = request.Email?.Trim();

        if (string.IsNullOrWhiteSpace(email)
            || !email.Contains(
                '@',
                StringComparison.Ordinal))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["email"] =
                    [
                        "A valid email address is required."
                    ]
                });
        }

        var user =
            await userManager.FindByEmailAsync(email);

        if (user is null
            || !await userManager.IsEmailConfirmedAsync(user))
        {
            return Results.Accepted(
                value: new
                {
                    message =
                        GenericForgotPasswordMessage
                });
        }

        try
        {
            var resetToken =
                await userManager
                    .GeneratePasswordResetTokenAsync(user);

            var encodedToken =
                WebEncoders.Base64UrlEncode(
                    Encoding.UTF8.GetBytes(
                        resetToken));

            await accountEmailSender
                .SendPasswordResetAsync(
                    email,
                    encodedToken,
                    cancellationToken);
        }
        catch (OperationCanceledException)
            when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            var logger =
                loggerFactory.CreateLogger(
                    typeof(IdentityEndpoints).FullName!);

            logger.LogWarning(
                exception,
                "Could not send a password reset message.");
        }

        return Results.Accepted(
            value: new
            {
                message =
                    GenericForgotPasswordMessage
            });
    }

    private static async Task<IResult> ResetPasswordAsync(
        ResetPasswordRequest request,
        UserManager<ApplicationUser> userManager,
        NotesDbContext dbContext,
        CancellationToken cancellationToken)
    {
        var email = request.Email?.Trim();

        if (string.IsNullOrWhiteSpace(email)
            || string.IsNullOrWhiteSpace(request.Token)
            || string.IsNullOrWhiteSpace(request.NewPassword))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["passwordReset"] =
                    [
                        "Email, reset token, and new password are required."
                    ]
                });
        }

        var user =
            await userManager.FindByEmailAsync(email);

        if (user is null)
        {
            return InvalidPasswordReset();
        }

        string decodedToken;

        try
        {
            var decodedBytes =
                WebEncoders.Base64UrlDecode(
                    request.Token);

            decodedToken =
                Encoding.UTF8.GetString(
                    decodedBytes);
        }
        catch (FormatException)
        {
            return InvalidPasswordReset();
        }

        await using var transaction =
            await dbContext.Database.BeginTransactionAsync(
                IsolationLevel.ReadCommitted,
                cancellationToken);

        var result =
            await userManager.ResetPasswordAsync(
                user,
                decodedToken,
                request.NewPassword);

        if (result.Succeeded)
        {
            var utcNow =
                DateTimeOffset.UtcNow;

            var activeSessions =
                await dbContext.RefreshSessions
                    .Where(
                        session =>
                            session.UserId == user.Id
                            && session.RevokedAt == null)
                    .ToListAsync(
                        cancellationToken);

            foreach (var session in activeSessions)
            {
                session.Revoke(
                    utcNow);
            }

            await dbContext.SaveChangesAsync(
                cancellationToken);

            await transaction.CommitAsync(
                cancellationToken);

            return Results.Ok(new
            {
                message =
                    "Password reset successfully."
            });
        }

        if (result.Errors.All(
                error =>
                    error.Code.StartsWith(
                        "Password",
                        StringComparison.Ordinal)))
        {
            var errors =
                result.Errors
                    .GroupBy(error => error.Code)
                    .ToDictionary(
                        group => group.Key,
                        group => group
                            .Select(
                                error =>
                                    error.Description)
                            .ToArray());

            return Results.ValidationProblem(
                errors);
        }

        return InvalidPasswordReset();
    }

    private const string RecoveryAdminSecretHeader =
        "X-Fasty-Recovery-Admin-Secret";

    private static async Task<IResult> IssuePasswordRecoveryCredentialAsync(
        IssuePasswordRecoveryCredentialRequest request,
        HttpContext httpContext,
        UserManager<ApplicationUser> userManager,
        NotesDbContext dbContext,
        IOptions<RecoveryAdminOptions> recoveryAdminOptionsAccessor,
        CancellationToken cancellationToken)
    {
        var options =
            recoveryAdminOptionsAccessor.Value;

        if (!options.Enabled)
        {
            return Results.NotFound();
        }

        if (!httpContext.Request.Headers.TryGetValue(
                RecoveryAdminSecretHeader,
                out var submittedSecretValues))
        {
            return Results.Unauthorized();
        }

        var submittedSecret =
            submittedSecretValues.ToString();

        if (!RecoveryAdminSecretMatches(
                submittedSecret,
                options.Secret))
        {
            return Results.Unauthorized();
        }

        var email =
            request.Email?.Trim();

        if (string.IsNullOrWhiteSpace(email))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["recovery"] =
                    [
                        "Email is required."
                    ]
                });
        }

        var user =
            await userManager.FindByEmailAsync(email);

        if (user is null)
        {
            return Results.NotFound();
        }

        var utcNow =
            DateTimeOffset.UtcNow;

        var expiresAt =
            utcNow.AddMinutes(
                options.CredentialLifetimeMinutes);

        var rawCredential =
            Microsoft.AspNetCore.WebUtilities.WebEncoders
                .Base64UrlEncode(
                    System.Security.Cryptography
                        .RandomNumberGenerator
                        .GetBytes(32));

        var credentialHash =
            Convert.ToHexString(
                System.Security.Cryptography.SHA256.HashData(
                    System.Text.Encoding.UTF8.GetBytes(
                        rawCredential)));

        await using var transaction =
            await dbContext.Database.BeginTransactionAsync(
                cancellationToken);

        _ =
            await dbContext.Users
                .FromSqlInterpolated(
                    $"""
                    SELECT *
                    FROM auth.users
                    WHERE "Id" = {user.Id}
                    FOR UPDATE
                    """)
                .SingleAsync(
                    cancellationToken);

        var activeCredentials =
            await dbContext.PasswordRecoveryCredentials
                .Where(
                    credential =>
                        credential.UserId == user.Id
                        && credential.ConsumedAt == null
                        && credential.ExpiresAt > utcNow)
                .ToListAsync(
                    cancellationToken);

        foreach (var activeCredential in activeCredentials)
        {
            activeCredential.Consume(
                utcNow);
        }

        var recoveryCredential =
            new PasswordRecoveryCredential(
                user.Id,
                credentialHash,
                utcNow,
                expiresAt);

        dbContext.PasswordRecoveryCredentials.Add(
            recoveryCredential);

        await dbContext.SaveChangesAsync(
            cancellationToken);

        await transaction.CommitAsync(
            cancellationToken);

        return Results.Ok(
            new IssuePasswordRecoveryCredentialResponse(
                rawCredential,
                expiresAt));
    }

    private static bool RecoveryAdminSecretMatches(
        string submittedSecret,
        string configuredSecret)
    {
        if (string.IsNullOrWhiteSpace(submittedSecret)
            || string.IsNullOrWhiteSpace(configuredSecret))
        {
            return false;
        }

        var submittedHash =
            System.Security.Cryptography.SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes(
                    submittedSecret));

        var configuredHash =
            System.Security.Cryptography.SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes(
                    configuredSecret));

        return System.Security.Cryptography.CryptographicOperations
            .FixedTimeEquals(
                submittedHash,
                configuredHash);
    }
    private static async Task<IResult> RedeemPasswordRecoveryCredentialAsync(
        RedeemPasswordRecoveryCredentialRequest request,
        UserManager<ApplicationUser> userManager,
        NotesDbContext dbContext,
        IOptions<RecoveryAdminOptions> recoveryAdminOptionsAccessor,
        CancellationToken cancellationToken)
    {
        var options =
            recoveryAdminOptionsAccessor.Value;

        if (!options.Enabled)
        {
            return Results.NotFound();
        }

        var email =
            request.Email?.Trim();

        if (string.IsNullOrWhiteSpace(email)
            || string.IsNullOrWhiteSpace(
                request.RecoveryCredential)
            || string.IsNullOrWhiteSpace(
                request.NewPassword))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["passwordRecovery"] =
                    [
                        "Email, recovery credential, and new password are required."
                    ]
                });
        }

        var user =
            await userManager.FindByEmailAsync(
                email);

        if (user is null)
        {
            return InvalidPasswordRecoveryCredential();
        }

        var credentialHash =
            Convert.ToHexString(
                System.Security.Cryptography.SHA256.HashData(
                    System.Text.Encoding.UTF8.GetBytes(
                        request.RecoveryCredential)));

        await using var transaction =
            await dbContext.Database.BeginTransactionAsync(
                IsolationLevel.ReadCommitted,
                cancellationToken);

        var recoveryCredential =
            await dbContext.PasswordRecoveryCredentials
                .FromSqlInterpolated(
                    $"""
                    SELECT *
                    FROM auth.password_recovery_credentials
                    WHERE "TokenHash" = {credentialHash}
                      AND "UserId" = {user.Id}
                    FOR UPDATE
                    """)
                .SingleOrDefaultAsync(
                    cancellationToken);

        var utcNow =
            DateTimeOffset.UtcNow;

        if (recoveryCredential is null
            || !recoveryCredential.IsActive(
                utcNow))
        {
            return InvalidPasswordRecoveryCredential();
        }

        var identityResetToken =
            await userManager.GeneratePasswordResetTokenAsync(
                user);

        var resetResult =
            await userManager.ResetPasswordAsync(
                user,
                identityResetToken,
                request.NewPassword);

        if (!resetResult.Succeeded)
        {
            if (resetResult.Errors.All(
                    error =>
                        error.Code.StartsWith(
                            "Password",
                            StringComparison.Ordinal)))
            {
                var errors =
                    resetResult.Errors
                        .GroupBy(
                            error => error.Code)
                        .ToDictionary(
                            group => group.Key,
                            group => group
                                .Select(
                                    error =>
                                        error.Description)
                                .ToArray());

                return Results.ValidationProblem(
                    errors);
            }

            return InvalidPasswordRecoveryCredential();
        }

        recoveryCredential.Consume(
            utcNow);

        var activeSessions =
            await dbContext.RefreshSessions
                .Where(
                    session =>
                        session.UserId == user.Id
                        && session.RevokedAt == null)
                .ToListAsync(
                    cancellationToken);

        foreach (var session in activeSessions)
        {
            session.Revoke(
                utcNow);
        }

        await dbContext.SaveChangesAsync(
            cancellationToken);

        await transaction.CommitAsync(
            cancellationToken);

        return Results.Ok(
            new
            {
                message =
                    "Password reset successfully. Sign in with your new password."
            });
    }
    private static async Task<IResult> ChangePasswordAsync(
        ChangePasswordRequest request,
        HttpContext httpContext,
        UserManager<ApplicationUser> userManager,
        NotesDbContext dbContext,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(
                request.CurrentPassword)
            || string.IsNullOrWhiteSpace(
                request.NewPassword))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["passwordChange"] =
                    [
                        "Current password and new password are required."
                    ]
                });
        }

        var userIdValue =
            httpContext.User.FindFirstValue(
                ClaimTypes.NameIdentifier);

        if (!Guid.TryParse(
                userIdValue,
                out var userId))
        {
            return Results.Unauthorized();
        }

        var user =
            await userManager.FindByIdAsync(
                userId.ToString());

        if (user is null)
        {
            return Results.Unauthorized();
        }

        await using var transaction =
            await dbContext.Database.BeginTransactionAsync(
                IsolationLevel.ReadCommitted,
                cancellationToken);

        var result =
            await userManager.ChangePasswordAsync(
                user,
                request.CurrentPassword,
                request.NewPassword);

        if (!result.Succeeded)
        {
            var currentPasswordInvalid =
                result.Errors.Any(
                    error =>
                        string.Equals(
                            error.Code,
                            "PasswordMismatch",
                            StringComparison.Ordinal));

            if (currentPasswordInvalid)
            {
                return Results.Json(
                    new
                    {
                        message =
                            "The current password is incorrect."
                    },
                    statusCode:
                        StatusCodes.Status400BadRequest);
            }

            var errors =
                result.Errors
                    .GroupBy(error => error.Code)
                    .ToDictionary(
                        group => group.Key,
                        group => group
                            .Select(
                                error =>
                                    error.Description)
                            .ToArray());

            return Results.ValidationProblem(
                errors);
        }

        var utcNow =
            DateTimeOffset.UtcNow;

        var activeSessions =
            await dbContext.RefreshSessions
                .Where(
                    session =>
                        session.UserId == user.Id
                        && session.RevokedAt == null)
                .ToListAsync(
                    cancellationToken);

        foreach (var session in activeSessions)
        {
            session.Revoke(
                utcNow);
        }

        await dbContext.SaveChangesAsync(
            cancellationToken);

        await transaction.CommitAsync(
            cancellationToken);

        return Results.Ok(
            new
            {
                message =
                    "Password changed successfully. Sign in again with your new password."
            });
    }

    private static async Task SendEmailConfirmationAsync(
        ApplicationUser user,
        string email,
        UserManager<ApplicationUser> userManager,
        IAccountEmailSender emailVerificationSender,
        CancellationToken cancellationToken)
    {
        var confirmationToken =
            await userManager
                .GenerateEmailConfirmationTokenAsync(user);

        var encodedToken =
            WebEncoders.Base64UrlEncode(
                Encoding.UTF8.GetBytes(
                    confirmationToken));

        await emailVerificationSender
            .SendVerificationAsync(
                email,
                encodedToken,
                cancellationToken);
    }

    private static async Task<IResult> ConfirmEmailAsync(
        ConfirmEmailRequest request,
        UserManager<ApplicationUser> userManager)
    {
        var email = request.Email?.Trim();

        if (string.IsNullOrWhiteSpace(email)
            || string.IsNullOrWhiteSpace(request.Token))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["confirmation"] =
                    [
                        "Email and confirmation token are required."
                    ]
                });
        }

        var user =
            await userManager.FindByEmailAsync(email);

        if (user is null)
        {
            return Results.BadRequest(new
            {
                message =
                    "The confirmation request is invalid or expired."
            });
        }

        string decodedToken;

        try
        {
            var decodedBytes =
                WebEncoders.Base64UrlDecode(
                    request.Token);

            decodedToken =
                Encoding.UTF8.GetString(
                    decodedBytes);
        }
        catch (FormatException)
        {
            return Results.BadRequest(new
            {
                message =
                    "The confirmation request is invalid or expired."
            });
        }

        var result =
            await userManager.ConfirmEmailAsync(
                user,
                decodedToken);

        if (!result.Succeeded)
        {
            return Results.BadRequest(new
            {
                message =
                    "The confirmation request is invalid or expired."
            });
        }

        return Results.Ok(new
        {
            message =
                "Email address confirmed successfully."
        });
    }

    private static async Task<IResult> GetGoogleLinkStatusAsync(
        HttpContext httpContext,
        UserManager<ApplicationUser> userManager)
    {
        var userIdValue = httpContext.User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!Guid.TryParse(userIdValue, out var userId))
        {
            return Results.Unauthorized();
        }

        var user = await userManager.FindByIdAsync(userId.ToString());
        if (user is null)
        {
            return Results.Unauthorized();
        }

        var logins = await userManager.GetLoginsAsync(user);
        return Results.Ok(new
        {
            linked = logins.Any(login => login.LoginProvider == "Google")
        });
    }

    private static async Task<IResult> LinkGoogleAsync(
        GoogleLinkRequest request,
        HttpContext httpContext,
        UserManager<ApplicationUser> userManager,
        IGoogleIdentityTokenValidator googleTokenValidator)
    {
        var idToken =
            request.IdToken?.Trim();

        if (string.IsNullOrWhiteSpace(idToken))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["googleLink"] =
                    [
                        "Google ID token is required."
                    ]
                });
        }

        if (!googleTokenValidator.IsConfigured)
        {
            return Results.NotFound();
        }

        var userIdValue =
            httpContext.User.FindFirstValue(
                ClaimTypes.NameIdentifier);

        if (!Guid.TryParse(
                userIdValue,
                out var userId))
        {
            return Results.Unauthorized();
        }

        var user =
            await userManager.FindByIdAsync(
                userId.ToString());

        if (user is null)
        {
            return Results.Unauthorized();
        }

        var googleIdentity =
            await googleTokenValidator.ValidateAsync(
                idToken);

        if (googleIdentity is null
            || !googleIdentity.EmailVerified)
        {
            return Results.Unauthorized();
        }

        if (string.IsNullOrWhiteSpace(user.Email)
            || !string.Equals(
                user.Email,
                googleIdentity.Email,
                StringComparison.OrdinalIgnoreCase))
        {
            return Results.Problem(
                title:
                    "Google account email does not match",
                detail:
                    "The Google account must use the same email address as the current Fasty account.",
                statusCode:
                    StatusCodes.Status409Conflict);
        }

        const string loginProvider =
            "Google";

        var linkedUser =
            await userManager.FindByLoginAsync(
                loginProvider,
                googleIdentity.Subject);

        if (linkedUser is not null)
        {
            if (linkedUser.Id == user.Id)
            {
                return Results.Ok(new
                {
                    message =
                        "Google account is already linked."
                });
            }

            return Results.Problem(
                title:
                    "Google account already linked",
                detail:
                    "This Google account is already linked to another Fasty account.",
                statusCode:
                    StatusCodes.Status409Conflict);
        }

        var loginInfo =
            new UserLoginInfo(
                loginProvider,
                googleIdentity.Subject,
                loginProvider);

        var result =
            await userManager.AddLoginAsync(
                user,
                loginInfo);

        if (!result.Succeeded)
        {
            var errors =
                result.Errors
                    .GroupBy(
                        error =>
                            error.Code)
                    .ToDictionary(
                        group =>
                            group.Key,
                        group =>
                            group
                                .Select(
                                    error =>
                                        error.Description)
                                .ToArray());

            return Results.ValidationProblem(
                errors);
        }

        return Results.Ok(new
        {
            message =
                "Google account linked successfully."
        });
    }

    private static async Task<IResult> ExchangeDesktopGoogleCodeAsync(
        GoogleDesktopExchangeRequest request,
        IGoogleAuthorizationCodeExchanger exchanger,
        CancellationToken cancellationToken)
    {
        var code =
            request.Code?.Trim();

        var codeVerifier =
            request.CodeVerifier?.Trim();

        var redirectUriValue =
            request.RedirectUri?.Trim();

        if (string.IsNullOrWhiteSpace(code)
            || string.IsNullOrWhiteSpace(codeVerifier)
            || string.IsNullOrWhiteSpace(redirectUriValue))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["googleDesktopExchange"] =
                    [
                        "Authorization code, PKCE verifier, and redirect URI are required."
                    ]
                });
        }

        if (!Uri.TryCreate(
                redirectUriValue,
                UriKind.Absolute,
                out var redirectUri)
            || !string.Equals(
                redirectUri.Scheme,
                Uri.UriSchemeHttp,
                StringComparison.OrdinalIgnoreCase)
            || !string.Equals(
                redirectUri.Host,
                "127.0.0.1",
                StringComparison.Ordinal)
            || redirectUri.Port <= 0
            || redirectUri.AbsolutePath != "/"
            || !string.IsNullOrEmpty(redirectUri.Query)
            || !string.IsNullOrEmpty(redirectUri.Fragment)
            || !string.IsNullOrEmpty(redirectUri.UserInfo))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["redirectUri"] =
                    [
                        "Desktop Google redirect URI must use an ephemeral 127.0.0.1 loopback callback."
                    ]
                });
        }

        if (!exchanger.IsConfigured)
        {
            return Results.NotFound();
        }

        var idToken =
            await exchanger.ExchangeAsync(
                code,
                codeVerifier,
                redirectUriValue,
                cancellationToken);

        if (string.IsNullOrWhiteSpace(idToken))
        {
            return Results.Unauthorized();
        }

        return Results.Ok(
            new
            {
                idToken
            });
    }

    private static async Task<IResult> GoogleLoginAsync(
        GoogleLoginRequest request,
        UserManager<ApplicationUser> userManager,
        IGoogleIdentityTokenValidator googleTokenValidator,
        IAccessTokenService accessTokenService,
        IRefreshTokenGenerator refreshTokenGenerator,
        IOptions<JwtTokenOptions> tokenOptionsAccessor,
        NotesDbContext dbContext,
        IUserActionTracker actionTracker,
        CancellationToken cancellationToken)
    {
        var idToken =
            request.IdToken?.Trim();

        var deviceName =
            request.DeviceName?.Trim();

        if (string.IsNullOrWhiteSpace(idToken)
            || string.IsNullOrWhiteSpace(deviceName))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["googleLogin"] =
                    [
                        "Google ID token and device name are required."
                    ]
                });
        }

        if (deviceName.Length > 200)
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["deviceName"] =
                    [
                        "Device name must not exceed 200 characters."
                    ]
                });
        }

        if (!googleTokenValidator.IsConfigured)
        {
            return Results.NotFound();
        }

        var googleIdentity =
            await googleTokenValidator.ValidateAsync(
                idToken);

        if (googleIdentity is null
            || !googleIdentity.EmailVerified)
        {
            return Results.Unauthorized();
        }

        const string loginProvider =
            "Google";

        var user =
            await userManager.FindByLoginAsync(
                loginProvider,
                googleIdentity.Subject);

        if (user is null)
        {
            var existingEmailUser =
                await userManager.FindByEmailAsync(
                    googleIdentity.Email);

            if (existingEmailUser is not null)
            {
                return Results.Problem(
                    title:
                        "Existing account requires linking",
                    detail:
                        "Sign in with your existing Fasty account first, then link Google from account settings.",
                    statusCode:
                        StatusCodes.Status409Conflict,
                    extensions:
                        new Dictionary<string, object?>
                        {
                            ["code"] =
                                "account_link_required"
                        });
            }

            user = new ApplicationUser
            {
                Id = Guid.NewGuid(),
                UserName = googleIdentity.Email,
                Email = googleIdentity.Email,
                EmailConfirmed =
                    IsGoogleAuthoritativeForEmail(
                        googleIdentity),
                CreatedAt =
                    DateTimeOffset.UtcNow
            };

            var creationResult =
                await userManager.CreateAsync(
                    user);

            if (!creationResult.Succeeded)
            {
                var errors =
                    creationResult.Errors
                        .GroupBy(
                            error =>
                                error.Code)
                        .ToDictionary(
                            group =>
                                group.Key,
                            group =>
                                group
                                    .Select(
                                        error =>
                                            error.Description)
                                    .ToArray());

                return Results.ValidationProblem(
                    errors);
            }

            var loginInfo =
                new UserLoginInfo(
                    loginProvider,
                    googleIdentity.Subject,
                    loginProvider);

            var loginResult =
                await userManager.AddLoginAsync(
                    user,
                    loginInfo);

            if (!loginResult.Succeeded)
            {
                await userManager.DeleteAsync(
                    user);

                var errors =
                    loginResult.Errors
                        .GroupBy(
                            error =>
                                error.Code)
                        .ToDictionary(
                            group =>
                                group.Key,
                            group =>
                                group
                                    .Select(
                                        error =>
                                            error.Description)
                                    .ToArray());

                return Results.ValidationProblem(
                    errors);
            }

            await actionTracker.TrackAsync(
                user.Id,
                UserActionTypes.UserRegistered);
        }

        return await IssueLoginSessionAsync(
            user,
            deviceName,
            accessTokenService,
            refreshTokenGenerator,
            tokenOptionsAccessor,
            dbContext,
            actionTracker,
            cancellationToken);
    }

    private static bool IsGoogleAuthoritativeForEmail(
        GoogleIdentity googleIdentity)
    {
        if (!googleIdentity.EmailVerified)
        {
            return false;
        }

        if (googleIdentity.Email.EndsWith(
                "@gmail.com",
                StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return !string.IsNullOrWhiteSpace(
            googleIdentity.HostedDomain);
    }

    private static async Task<IResult> LoginAsync(
        LoginRequest request,
        UserManager<ApplicationUser> userManager,
        SignInManager<ApplicationUser> signInManager,
        IAccessTokenService accessTokenService,
        IRefreshTokenGenerator refreshTokenGenerator,
        IOptions<JwtTokenOptions> tokenOptionsAccessor,
        NotesDbContext dbContext,
        IUserActionTracker actionTracker,
        CancellationToken cancellationToken)
    {
        var email = request.Email?.Trim();
        var deviceName = request.DeviceName?.Trim();

        if (string.IsNullOrWhiteSpace(email)
            || string.IsNullOrWhiteSpace(request.Password)
            || string.IsNullOrWhiteSpace(deviceName))
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["login"] =
                    [
                        "Email, password, and device name are required."
                    ]
                });
        }

        if (deviceName.Length > 200)
        {
            return Results.ValidationProblem(
                new Dictionary<string, string[]>
                {
                    ["deviceName"] =
                    [
                        "Device name must not exceed 200 characters."
                    ]
                });
        }

        var user =
            await userManager.FindByEmailAsync(email);

        if (user is null)
        {
            return InvalidCredentials();
        }

        var signInResult =
            await signInManager.CheckPasswordSignInAsync(
                user,
                request.Password,
                lockoutOnFailure: true);

        if (signInResult.IsLockedOut)
        {
            return Results.Problem(
                title: "Account temporarily locked",
                detail:
                    "Too many unsuccessful login attempts. Try again later.",
                statusCode:
                    StatusCodes.Status423Locked);
        }

        if (!signInResult.Succeeded)
        {
            return InvalidCredentials();
        }

        return await IssueLoginSessionAsync(
            user,
            deviceName,
            accessTokenService,
            refreshTokenGenerator,
            tokenOptionsAccessor,
            dbContext,
            actionTracker,
            cancellationToken);
    }

    private static async Task<IResult> IssueLoginSessionAsync(
        ApplicationUser user,
        string deviceName,
        IAccessTokenService accessTokenService,
        IRefreshTokenGenerator refreshTokenGenerator,
        IOptions<JwtTokenOptions> tokenOptionsAccessor,
        NotesDbContext dbContext,
        IUserActionTracker actionTracker,
        CancellationToken cancellationToken)
    {
        var utcNow =
            DateTimeOffset.UtcNow;

        var options =
            tokenOptionsAccessor.Value;

        var accessToken =
            accessTokenService.Generate(
                user,
                utcNow);

        var rawRefreshToken =
            refreshTokenGenerator.Generate();

        var refreshTokenHash =
            refreshTokenGenerator.Hash(
                rawRefreshToken);

        var refreshTokenExpiresAt =
            utcNow.AddDays(
                options.RefreshTokenDays);

        var refreshSession =
            new RefreshSession(
                user.Id,
                refreshTokenHash,
                deviceName,
                utcNow,
                refreshTokenExpiresAt);

        dbContext.RefreshSessions.Add(
            refreshSession);

        await dbContext.SaveChangesAsync(
            cancellationToken);

        await actionTracker.TrackAsync(
            user.Id,
            UserActionTypes.UserLoggedIn);

        return Results.Ok(
            new LoginResponse(
                user.Email
                    ?? throw new InvalidOperationException(
                        "Authenticated user is missing an email address."),
                accessToken.Token,
                accessToken.ExpiresAt,
                rawRefreshToken,
                refreshTokenExpiresAt,
                refreshSession.Id));
    }

    private static async Task<IResult> RefreshAsync(
        RefreshTokenRequest request,
        UserManager<ApplicationUser> userManager,
        IAccessTokenService accessTokenService,
        IRefreshTokenGenerator refreshTokenGenerator,
        IOptions<JwtTokenOptions> tokenOptionsAccessor,
        NotesDbContext dbContext,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(
                request.RefreshToken))
        {
            return InvalidRefreshToken();
        }

        string submittedTokenHash;

        try
        {
            submittedTokenHash =
                refreshTokenGenerator.Hash(
                    request.RefreshToken);
        }
        catch (ArgumentException)
        {
            return InvalidRefreshToken();
        }

        await using var transaction =
            await dbContext.Database.BeginTransactionAsync(
                IsolationLevel.ReadCommitted,
                cancellationToken);

        var existingSession =
            await dbContext.RefreshSessions
                .FromSqlInterpolated(
                    $"""
                    SELECT *
                    FROM auth.refresh_sessions
                    WHERE "TokenHash" = {submittedTokenHash}
                    FOR UPDATE
                    """)
                .SingleOrDefaultAsync(
                    cancellationToken);

        if (existingSession is null)
        {
            await transaction.RollbackAsync(
                cancellationToken);

            return InvalidRefreshToken();
        }

        var utcNow = DateTimeOffset.UtcNow;

        if (!existingSession.IsActive(utcNow))
        {
            if (existingSession.ReplacedBySessionId
                is not null)
            {
                await RevokeReplacementChainAsync(
                    existingSession
                        .ReplacedBySessionId
                        .Value,
                    utcNow,
                    dbContext,
                    cancellationToken);

                await dbContext.SaveChangesAsync(
                    cancellationToken);

                await transaction.CommitAsync(
                    cancellationToken);
            }
            else
            {
                await transaction.RollbackAsync(
                    cancellationToken);
            }

            return InvalidRefreshToken();
        }

        var user =
            await userManager.FindByIdAsync(
                existingSession.UserId.ToString());

        if (user is null
            || !user.EmailConfirmed
            || await userManager.IsLockedOutAsync(user))
        {
            existingSession.Revoke(utcNow);

            await dbContext.SaveChangesAsync(
                cancellationToken);

            await transaction.CommitAsync(
                cancellationToken);

            return InvalidRefreshToken();
        }

        var options =
            tokenOptionsAccessor.Value;

        var newRawRefreshToken =
            refreshTokenGenerator.Generate();

        var newRefreshTokenHash =
            refreshTokenGenerator.Hash(
                newRawRefreshToken);

        var newRefreshTokenExpiresAt =
            utcNow.AddDays(
                options.RefreshTokenDays);

        var replacementSession =
            new RefreshSession(
                user.Id,
                newRefreshTokenHash,
                existingSession.DeviceName,
                utcNow,
                newRefreshTokenExpiresAt);

        dbContext.RefreshSessions.Add(
            replacementSession);

        existingSession.MarkUsed(utcNow);

        existingSession.Revoke(
            utcNow,
            replacementSession.Id);

        var accessToken =
            accessTokenService.Generate(
                user,
                utcNow);

        await dbContext.SaveChangesAsync(
            cancellationToken);

        await transaction.CommitAsync(
            cancellationToken);

        return Results.Ok(
            new LoginResponse(
                user.Email
                    ?? throw new InvalidOperationException(
                        "Authenticated user is missing an email address."),
                accessToken.Token,
                accessToken.ExpiresAt,
                newRawRefreshToken,
                newRefreshTokenExpiresAt,
                replacementSession.Id));
    }

    private static async Task<IResult> LogoutAsync(
        RefreshTokenRequest request,
        IRefreshTokenGenerator refreshTokenGenerator,
        NotesDbContext dbContext,
        IUserActionTracker actionTracker,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(
                request.RefreshToken))
        {
            return Results.NoContent();
        }

        string submittedTokenHash;

        try
        {
            submittedTokenHash =
                refreshTokenGenerator.Hash(
                    request.RefreshToken);
        }
        catch (ArgumentException)
        {
            return Results.NoContent();
        }

        await using var transaction =
            await dbContext.Database.BeginTransactionAsync(
                IsolationLevel.ReadCommitted,
                cancellationToken);

        var session =
            await dbContext.RefreshSessions
                .FromSqlInterpolated(
                    $"""
                    SELECT *
                    FROM auth.refresh_sessions
                    WHERE "TokenHash" = {submittedTokenHash}
                    FOR UPDATE
                    """)
                .SingleOrDefaultAsync(
                    cancellationToken);

        if (session is null)
        {
            await transaction.RollbackAsync(
                cancellationToken);

            return Results.NoContent();
        }

        session.Revoke(
            DateTimeOffset.UtcNow);

        await dbContext.SaveChangesAsync(
            cancellationToken);

        await transaction.CommitAsync(
            cancellationToken);

        await actionTracker.TrackAsync(
            session.UserId,
            UserActionTypes.UserLoggedOut);

        return Results.NoContent();
    }

    private static async Task RevokeReplacementChainAsync(
        Guid sessionId,
        DateTimeOffset utcNow,
        NotesDbContext dbContext,
        CancellationToken cancellationToken)
    {
        const int maximumChainLength = 100;

        var currentSessionId = sessionId;

        for (var index = 0;
             index < maximumChainLength;
             index++)
        {
            var session =
                await dbContext.RefreshSessions
                    .FromSqlInterpolated(
                        $"""
                        SELECT *
                        FROM auth.refresh_sessions
                        WHERE "Id" = {currentSessionId}
                        FOR UPDATE
                        """)
                    .SingleOrDefaultAsync(
                        cancellationToken);

            if (session is null)
            {
                return;
            }

            session.Revoke(utcNow);

            if (session.ReplacedBySessionId
                is null)
            {
                return;
            }

            currentSessionId =
                session
                    .ReplacedBySessionId
                    .Value;
        }

        throw new InvalidOperationException(
            "Refresh-session replacement chain exceeded the safety limit.");
    }

    private static IResult InvalidPasswordRecoveryCredential()
    {
        return Results.BadRequest(
            new
            {
                message =
                    "The recovery credential is invalid or expired."
            });
    }
    private static IResult InvalidPasswordReset()
    {
        return Results.BadRequest(new
        {
            message =
                "The password reset request is invalid or expired."
        });
    }
    private static IResult InvalidCredentials()
    {
        return Results.Json(
            new
            {
                message =
                    "The email or password is incorrect."
            },
            statusCode:
                StatusCodes.Status401Unauthorized);
    }

    private static IResult InvalidRefreshToken()
    {
        return Results.Json(
            new
            {
                message =
                    "The refresh token is invalid or expired."
            },
            statusCode:
                StatusCodes.Status401Unauthorized);
    }
}
