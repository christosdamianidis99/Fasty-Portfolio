using Fasty.Api.Modules.Identity;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace Fasty.Api.Modules.Notes;

public sealed class NotesDbContext(
    DbContextOptions<NotesDbContext> options)
    : IdentityDbContext<ApplicationUser, IdentityRole<Guid>, Guid>(options)
{
    public DbSet<Note> Notes => Set<Note>();

    public DbSet<RefreshSession> RefreshSessions =>
    Set<RefreshSession>();

    public DbSet<PasswordRecoveryCredential> PasswordRecoveryCredentials =>
        Set<PasswordRecoveryCredential>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        ConfigureIdentity(modelBuilder);
        ConfigureNotes(modelBuilder);
    }

    private static void ConfigureIdentity(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ApplicationUser>(entity =>
        {
            entity.ToTable("users", "auth");

            entity.Property(user => user.CreatedAt)
                .IsRequired();

            entity.HasIndex(user => user.NormalizedEmail)
                .HasDatabaseName("ix_users_normalized_email");
        });

        modelBuilder.Entity<IdentityRole<Guid>>()
            .ToTable("roles", "auth");

        modelBuilder.Entity<IdentityUserRole<Guid>>()
            .ToTable("user_roles", "auth");

        modelBuilder.Entity<IdentityUserClaim<Guid>>()
            .ToTable("user_claims", "auth");

        modelBuilder.Entity<IdentityUserLogin<Guid>>()
            .ToTable("user_logins", "auth");

        modelBuilder.Entity<IdentityRoleClaim<Guid>>()
            .ToTable("role_claims", "auth");

        modelBuilder.Entity<IdentityUserToken<Guid>>()
            .ToTable("user_tokens", "auth");

        modelBuilder.Entity<RefreshSession>(entity =>
{
    entity.ToTable("refresh_sessions", "auth");

    entity.HasKey(session => session.Id);

    entity.Property(session => session.TokenHash)
        .HasMaxLength(128)
        .IsRequired();

    entity.Property(session => session.DeviceName)
        .HasMaxLength(200)
        .IsRequired();

    entity.Property(session => session.CreatedAt)
        .IsRequired();

    entity.Property(session => session.ExpiresAt)
        .IsRequired();

    entity.HasIndex(session => session.TokenHash)
        .IsUnique();

    entity.HasIndex(session => new
    {
        session.UserId,
        session.RevokedAt,
        session.ExpiresAt
    });

    entity.HasOne(session => session.User)
        .WithMany(user => user.RefreshSessions)
        .HasForeignKey(session => session.UserId)
        .OnDelete(DeleteBehavior.Cascade);

    entity.HasOne<RefreshSession>()
        .WithMany()
        .HasForeignKey(session => session.ReplacedBySessionId)
        .OnDelete(DeleteBehavior.Restrict);
});


        modelBuilder.Entity<PasswordRecoveryCredential>(entity =>
        {
            entity.ToTable("password_recovery_credentials", "auth");

            entity.HasKey(credential => credential.Id);

            entity.Property(credential => credential.TokenHash)
                .HasMaxLength(128)
                .IsRequired();

            entity.Property(credential => credential.CreatedAt)
                .IsRequired();

            entity.Property(credential => credential.ExpiresAt)
                .IsRequired();

            entity.HasIndex(credential => credential.TokenHash)
                .IsUnique();

            entity.HasIndex(credential => new
            {
                credential.UserId,
                credential.ConsumedAt,
                credential.ExpiresAt
            });

            entity.HasOne(credential => credential.User)
                .WithMany(user => user.PasswordRecoveryCredentials)
                .HasForeignKey(credential => credential.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }

    private static void ConfigureNotes(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Note>(entity =>
        {
            entity.ToTable("notes", "notes");
            entity.HasKey(note => note.Id);

            entity.Property(note => note.Title)
                .HasMaxLength(300)
                .IsRequired();

            entity.Property(note => note.Content)
                .IsRequired();

            entity.Property(note => note.CreatedAt)
                .IsRequired();

            entity.Property(note => note.UpdatedAt)
                .IsRequired();

            entity.Property(note => note.IsDeleted)
                .IsRequired()
                .HasDefaultValue(false);

            entity.HasOne(note => note.User)
                .WithMany(user => user.Notes)
                .HasForeignKey(note => note.UserId)
                .OnDelete(DeleteBehavior.Cascade)
                .IsRequired();

            entity.HasIndex(note => new
            {
                note.UserId,
                note.UpdatedAt
            });
        });
    }
}