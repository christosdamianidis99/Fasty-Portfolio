using Fasty.Api.Modules.Monitoring;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
namespace Fasty.Api.Modules.Notes;

public static class NotesEndpoints
{
    public static IEndpointRouteBuilder MapNotesEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints
    .MapGroup("/api/v1/notes")
    .WithTags("Notes")
    .RequireAuthorization();

        group.MapGet("/", async (
            ClaimsPrincipal principal,
            NotesDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetUserId(principal, out var userId))
            {
                return Results.Unauthorized();
            }

            var notes = await dbContext.Notes
                .AsNoTracking()
                .Where(note => note.UserId == userId)
                .OrderByDescending(note => note.UpdatedAt)
                .Select(note => NoteResponse.From(note))
                .ToListAsync(cancellationToken);

            return Results.Ok(notes);
        });

        group.MapGet("/{id:guid}", async (
            Guid id,
            ClaimsPrincipal principal,
            NotesDbContext dbContext,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetUserId(principal, out var userId))
            {
                return Results.Unauthorized();
            }

            var note = await dbContext.Notes
                .AsNoTracking()
                .SingleOrDefaultAsync(
                    note => note.Id == id && note.UserId == userId,
                    cancellationToken);

            return note is null
                ? Results.NotFound()
                : Results.Ok(NoteResponse.From(note));
        });

        group.MapPost("/", async (
            CreateNoteRequest request,
            ClaimsPrincipal principal,
            NotesDbContext dbContext,
            IUserActionTracker actionTracker,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetUserId(principal, out var userId))
            {
                return Results.Unauthorized();
            }

            var validationError = Validate(request.Title, request.Content);

            if (validationError is not null)
            {
                return Results.ValidationProblem(validationError);
            }

            var now = DateTimeOffset.UtcNow;

            var note = new Note(
                Guid.CreateVersion7(),
                userId,
                request.Title,
                request.Content,
                now);

            dbContext.Notes.Add(note);
            await dbContext.SaveChangesAsync(cancellationToken);

            await actionTracker.TrackAsync(
                userId,
                UserActionTypes.NoteCreated);

            return Results.Created(
                $"/api/v1/notes/{note.Id}",
                NoteResponse.From(note));
        });

        group.MapPut("/{id:guid}", async (
            Guid id,
            UpsertNoteRequest request,
            ClaimsPrincipal principal,
            NotesDbContext dbContext,
            IUserActionTracker actionTracker,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetUserId(principal, out var userId))
            {
                return Results.Unauthorized();
            }

            var validationError = Validate(request.Title, request.Content);

            if (validationError is not null)
            {
                return Results.ValidationProblem(validationError);
            }

            var note = await dbContext.Notes
                .SingleOrDefaultAsync(
                    note => note.Id == id && note.UserId == userId,
                    cancellationToken);

            var noteWasCreated = note is null;

            if (note is null)
            {
                var idIsAlreadyUsed = await dbContext.Notes
                    .AnyAsync(
                        note => note.Id == id,
                        cancellationToken);

                if (idIsAlreadyUsed)
                {
                    return Results.Conflict(new
                    {
                        message = "The note identifier is unavailable."
                    });
                }

                note = new Note(
                    id,
                    userId,
                    request.Title,
                    request.Content,
                    request.CreatedAt);

                if (request.UpdatedAt != request.CreatedAt)
                {
                    note.Update(
                        request.Title,
                        request.Content,
                        request.UpdatedAt);
                }

                dbContext.Notes.Add(note);
            }
            else
            {
                note.Update(
                    request.Title,
                    request.Content,
                    request.UpdatedAt);
            }

            await dbContext.SaveChangesAsync(cancellationToken);

            await actionTracker.TrackAsync(
                userId,
                noteWasCreated
                    ? UserActionTypes.NoteCreated
                    : UserActionTypes.NoteUpdated);

            return Results.Ok(NoteResponse.From(note));
        });

        group.MapDelete("/{id:guid}", async (
            Guid id,
            DateTimeOffset? updatedAt,
            ClaimsPrincipal principal,
            NotesDbContext dbContext,
            IUserActionTracker actionTracker,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetUserId(principal, out var userId))
            {
                return Results.Unauthorized();
            }

            var note = await dbContext.Notes
                .SingleOrDefaultAsync(
                    note => note.Id == id && note.UserId == userId,
                    cancellationToken);

            if (note is null)
            {
                return Results.NoContent();
            }

            var deletedAt =
                updatedAt ?? DateTimeOffset.UtcNow;

            var noteWasAlreadyDeleted =
                note.IsDeleted;

            var changed = noteWasAlreadyDeleted
                ? note.Purge(deletedAt)
                : note.Delete(deletedAt);

            if (changed)
            {
                await dbContext.SaveChangesAsync(cancellationToken);

                await actionTracker.TrackAsync(
                    userId,
                    noteWasAlreadyDeleted
                        ? UserActionTypes.NotePurged
                        : UserActionTypes.NoteDeleted);
            }

            return Results.NoContent();
        });

        return endpoints;
    }
    private static bool TryGetUserId(
        ClaimsPrincipal principal,
        out Guid userId)
    {
        var userIdValue =
            principal.FindFirstValue(ClaimTypes.NameIdentifier);

        return Guid.TryParse(userIdValue, out userId)
            && userId != Guid.Empty;
    }
    private static Dictionary<string, string[]>? Validate(string title, string content)
    {
        var errors = new Dictionary<string, string[]>();

        if (string.IsNullOrWhiteSpace(title))
        {
            errors[nameof(title)] = ["A title is required."];
        }
        else if (title.Trim().Length > 300)
        {
            errors[nameof(title)] = ["The title cannot exceed 300 characters."];
        }

        if (content is null)
        {
            errors[nameof(content)] = ["Content is required."];
        }

        return errors.Count == 0 ? null : errors;
    }

    public sealed record CreateNoteRequest(string Title, string Content);

    public sealed record UpsertNoteRequest(
        string Title,
        string Content,
        DateTimeOffset CreatedAt,
        DateTimeOffset UpdatedAt);

    public sealed record NoteResponse(
        Guid Id,
        string Title,
        string Content,
        DateTimeOffset CreatedAt,
        DateTimeOffset UpdatedAt,
        bool IsDeleted)
    {
        public static NoteResponse From(Note note) =>
            new(
                note.Id,
                note.Title,
                note.Content,
                note.CreatedAt,
                note.UpdatedAt,
                note.IsDeleted);
    }
}
