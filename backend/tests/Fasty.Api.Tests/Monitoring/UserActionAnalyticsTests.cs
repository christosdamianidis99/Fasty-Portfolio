using Fasty.Api.Modules.Monitoring;
using Microsoft.Extensions.Options;
using Xunit;

namespace Fasty.Api.Tests.Monitoring;

public sealed class UserActionAnalyticsTests
{
    [Fact]
    public async Task Track_ForSameUser_UsesStableIdentifier()
    {
        var store = CreateStore();
        var tracker = CreateTracker(store);

        var userId =
            Guid.Parse(
                "11111111-2222-3333-4444-555555555555");

        await tracker.TrackAsync(
            userId,
            UserActionTypes.NoteCreated);

        await tracker.TrackAsync(
            userId,
            UserActionTypes.NoteUpdated);

        var actions = await store.GetRecentAsync();

        Assert.Equal(2, actions.Count);
        Assert.Equal(
            actions[0].AnonymizedUserId,
            actions[1].AnonymizedUserId);

        Assert.Equal(
            8,
            actions[0].AnonymizedUserId.Length);
    }

    [Fact]
    public async Task GetSummary_CountsActionsAndUsers()
    {
        var store = CreateStore();
        var tracker = CreateTracker(store);

        await tracker.TrackAsync(
            Guid.Parse(
                "11111111-2222-3333-4444-555555555555"),
            UserActionTypes.NoteCreated);

        await tracker.TrackAsync(
            Guid.Parse(
                "11111111-2222-3333-4444-555555555555"),
            UserActionTypes.NoteUpdated);

        await tracker.TrackAsync(
            Guid.Parse(
                "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
            UserActionTypes.NoteCreated);

        var summary = await store.GetSummaryAsync();

        Assert.Equal(3, summary.TotalActions);
        Assert.Equal(2, summary.ActiveUsers);

        Assert.Equal(
            2,
            summary.ActionsByType[
                UserActionTypes.NoteCreated]);

        Assert.Equal(
            1,
            summary.ActionsByType[
                UserActionTypes.NoteUpdated]);
    }

    [Fact]
    public async Task GetUsers_ReturnsPerUserMetrics()
    {
        var store = CreateStore();
        var tracker = CreateTracker(store);

        var firstUser =
            Guid.Parse(
                "11111111-2222-3333-4444-555555555555");

        var secondUser =
            Guid.Parse(
                "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");

        await tracker.TrackAsync(
            firstUser,
            UserActionTypes.NoteCreated);

        await tracker.TrackAsync(
            firstUser,
            UserActionTypes.UserLoggedIn);

        await tracker.TrackAsync(
            secondUser,
            UserActionTypes.WorkspaceStateChanged);

        var users = await store.GetUsersAsync();

        Assert.Equal(2, users.Count);

        var firstUserSummary = Assert.Single(
            users,
            user => user.TotalActions == 2);

        Assert.Equal(
            1,
            firstUserSummary.ActionsByType[
                UserActionTypes.NoteCreated]);

        Assert.Equal(
            1,
            firstUserSummary.ActionsByType[
                UserActionTypes.UserLoggedIn]);
    }

    [Fact]
    public async Task GetRecentForUser_FiltersOtherUsers()
    {
        var store = CreateStore();
        var tracker = CreateTracker(store);

        var firstUser =
            Guid.Parse(
                "11111111-2222-3333-4444-555555555555");

        var secondUser =
            Guid.Parse(
                "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");

        await tracker.TrackAsync(
            firstUser,
            UserActionTypes.NoteCreated);

        await tracker.TrackAsync(
            secondUser,
            UserActionTypes.NoteUpdated);

        var firstSummary = (await store.GetUsersAsync())
            .Single(
                user =>
                    user.ActionsByType.ContainsKey(
                        UserActionTypes.NoteCreated));

        var actions = await store.GetRecentForUserAsync(
            firstSummary.AnonymizedUserId);

        var action = Assert.Single(actions);

        Assert.Equal(
            UserActionTypes.NoteCreated,
            action.Action);
    }

    [Fact]
    public async Task Track_WhenMonitoringDisabled_DoesNothing()
    {
        var store = CreateStore();

        var tracker = new UserActionTracker(
            store,
            Options.Create(
                new MonitoringOptions
                {
                    Enabled = false,
                    AnonymizationKey =
                        "test-monitoring-key"
                }));

        await tracker.TrackAsync(
            Guid.NewGuid(),
            UserActionTypes.NoteCreated);

        Assert.Empty(await store.GetRecentAsync());
    }

    private static InMemoryUserActionStore CreateStore()
    {
        return new InMemoryUserActionStore(
            Options.Create(
                new MonitoringOptions
                {
                    ActionCapacity = 100
                }));
    }

    private static UserActionTracker CreateTracker(
        IUserActionStore store)
    {
        return new UserActionTracker(
            store,
            Options.Create(
                new MonitoringOptions
                {
                    Enabled = true,
                    AnonymizationKey =
                        "test-monitoring-key"
                }));
    }
}
