using System.Collections.Concurrent;
using Fasty.Api.Modules.Identity.Email;

namespace Fasty.Api.Tests;

internal sealed class TestAccountEmailSender
    : IAccountEmailSender
{
    private readonly ConcurrentQueue<SentVerification> _sent = new();

    private readonly ConcurrentQueue<SentPasswordReset>
        _passwordResets = new();

    public bool IsAvailable { get; set; } = true;

    public Exception? SendException { get; set; }

    public IReadOnlyCollection<SentVerification> Sent =>
        _sent.ToArray();

    public IReadOnlyCollection<SentPasswordReset> PasswordResets =>
        _passwordResets.ToArray();

    public Task SendVerificationAsync(
        string email,
        string confirmationToken,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        EnsureAvailable();

        _sent.Enqueue(
            new SentVerification(
                email,
                confirmationToken));

        return Task.CompletedTask;
    }

    public Task SendPasswordResetAsync(
        string email,
        string passwordResetToken,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        EnsureAvailable();

        _passwordResets.Enqueue(
            new SentPasswordReset(
                email,
                passwordResetToken));

        return Task.CompletedTask;
    }

    public void Reset()
    {
        IsAvailable = true;
        SendException = null;

        while (_sent.TryDequeue(out _))
        {
        }

        while (_passwordResets.TryDequeue(out _))
        {
        }
    }

    private void EnsureAvailable()
    {
        if (!IsAvailable)
        {
            throw new InvalidOperationException(
                "The test email sender is unavailable.");
        }

        if (SendException is not null)
        {
            throw SendException;
        }
    }

    public sealed record SentVerification(
        string Email,
        string ConfirmationToken);

    public sealed record SentPasswordReset(
        string Email,
        string PasswordResetToken);
}
