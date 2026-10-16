namespace Fasty.Api.Modules.Monitoring;

public static class UserAnalyticsDashboardPage
{
    public const string Html = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta
    name="viewport"
    content="width=device-width, initial-scale=1">

  <title>Fasty User Analytics</title>

  <style>
    :root {
      color-scheme: light;
      font-family:
        Inter,
        ui-sans-serif,
        system-ui,
        -apple-system,
        BlinkMacSystemFont,
        "Segoe UI",
        sans-serif;

      background: #f7f5ff;
      color: #28243d;
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      min-height: 100vh;
      background:
        radial-gradient(
          circle at top left,
          #ebe4ff,
          transparent 35%),
        radial-gradient(
          circle at top right,
          #dff8ef,
          transparent 30%),
        #f7f5ff;
    }

    main {
      width: min(1180px, calc(100% - 32px));
      margin: 0 auto;
      padding: 42px 0 64px;
    }

    h1 {
      margin: 0;
      font-size: clamp(1.9rem, 5vw, 3rem);
      letter-spacing: -0.04em;
    }

    h2 {
      margin: 0;
      font-size: 1.2rem;
    }

    .subtitle {
      margin: 8px 0 4px;
      color: #6e6882;
    }

    .updated {
      margin: 0 0 28px;
      color: #8b849d;
      font-size: 0.9rem;
    }

    .navigation {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin: 20px 0 28px;
    }

    .navigation a {
      padding: 9px 14px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.82);
      border: 1px solid rgba(80, 70, 120, 0.12);
      color: #514775;
      text-decoration: none;
      font-weight: 650;
    }

    .cards {
      display: grid;
      grid-template-columns:
        repeat(auto-fit, minmax(190px, 1fr));
      gap: 16px;
      margin-bottom: 24px;
    }

    .card,
    .panel {
      background: rgba(255, 255, 255, 0.84);
      border: 1px solid rgba(80, 70, 120, 0.12);
      box-shadow: 0 16px 45px rgba(78, 62, 125, 0.08);
      backdrop-filter: blur(16px);
    }

    .card {
      border-radius: 22px;
      padding: 20px;
    }

    .card-label {
      color: #777087;
      font-size: 0.88rem;
      font-weight: 650;
    }

    .card-value {
      margin-top: 8px;
      font-size: 2rem;
      font-weight: 780;
      letter-spacing: -0.04em;
    }

    .panel {
      border-radius: 24px;
      overflow: hidden;
      margin-bottom: 24px;
    }

    .panel-header {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      align-items: center;
      padding: 20px 22px;
      border-bottom: 1px solid rgba(80, 70, 120, 0.1);
    }

    .muted {
      color: #898297;
    }

    .breakdown {
      display: grid;
      grid-template-columns:
        repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
      padding: 20px;
    }

    .breakdown-item {
      padding: 14px 16px;
      border-radius: 16px;
      background: #f8f6ff;
    }

    .breakdown-name {
      color: #6e6882;
      font-size: 0.84rem;
    }

    .breakdown-count {
      margin-top: 4px;
      font-size: 1.35rem;
      font-weight: 760;
    }

    .table-wrap {
      overflow-x: auto;
    }

    table {
      width: 100%;
      border-collapse: collapse;
      min-width: 680px;
    }

    th,
    td {
      padding: 14px 18px;
      text-align: left;
      border-bottom: 1px solid rgba(80, 70, 120, 0.08);
    }

    th {
      color: #6e6882;
      font-size: 0.78rem;
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }

    tr:last-child td {
      border-bottom: 0;
    }

    .mono {
      font-family:
        "SFMono-Regular",
        Consolas,
        "Liberation Mono",
        monospace;
      font-size: 0.88rem;
    }

    .action {
      display: inline-flex;
      align-items: center;
      padding: 5px 9px;
      border-radius: 999px;
      background: #ece7ff;
      color: #504478;
      font-size: 0.82rem;
      font-weight: 700;
    }

    @media (max-width: 640px) {
      main {
        width: min(100% - 20px, 1180px);
        padding-top: 24px;
      }

      .panel-header {
        align-items: flex-start;
        flex-direction: column;
      }
    }
  </style>
</head>

<body>
  <main>
    <h1>Fasty User Analytics ✨</h1>

    <p class="subtitle">
      Meaningful server-confirmed actions · anonymized users · no user content
    </p>

    <p id="updated" class="updated">
      Loading…
    </p>

    <nav class="navigation">
      <a href="/monitoring">Operational monitoring</a>
      <a href="/monitoring/analytics">User analytics</a>
      <a href="/monitoring/users">User details</a>
    </nav>

    <section class="cards">
      <article class="card">
        <div class="card-label">Total actions</div>
        <div id="total-actions" class="card-value">—</div>
      </article>

      <article class="card">
        <div class="card-label">Active users</div>
        <div id="active-users" class="card-value">—</div>
      </article>

      <article class="card">
        <div class="card-label">Notes created</div>
        <div id="notes-created" class="card-value">—</div>
      </article>

      <article class="card">
        <div class="card-label">Notes updated</div>
        <div id="notes-updated" class="card-value">—</div>
      </article>

      <article class="card">
        <div class="card-label">Notes deleted</div>
        <div id="notes-deleted" class="card-value">—</div>
      </article>

      <article class="card">
        <div class="card-label">Workspace changes</div>
        <div id="workspace-changes" class="card-value">—</div>
      </article>
    </section>

    <section class="panel">
      <div class="panel-header">
        <h2>Action breakdown</h2>
        <span class="muted">Current in-memory window</span>
      </div>

      <div id="breakdown" class="breakdown">
        <div class="muted">Loading…</div>
      </div>
    </section>

    <section class="panel">
      <div class="panel-header">
        <h2>Recent user actions</h2>
        <span class="muted">Auto-refresh every 10s</span>
      </div>

      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Local time</th>
              <th>User</th>
              <th>Action</th>
            </tr>
          </thead>

          <tbody id="actions-body">
            <tr>
              <td colspan="3" class="muted">
                Loading…
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </main>

  <script>
    const escapeHtml = value =>
      String(value)
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');

    const readableAction = value =>
      String(value)
        .replaceAll('_', ' ')
        .replace(/\b\w/g, character => character.toUpperCase());

    const actionCount = (summary, action) =>
      summary.actionsByType?.[action] ?? 0;

    async function refreshAnalytics() {
      try {
        const [summaryResponse, actionsResponse] =
          await Promise.all([
            fetch(
              '/monitoring/actions/summary',
              { cache: 'no-store' }),
            fetch(
              '/monitoring/actions?limit=100',
              { cache: 'no-store' })
          ]);

        if (!summaryResponse.ok || !actionsResponse.ok) {
          throw new Error('Analytics request failed.');
        }

        const summary = await summaryResponse.json();
        const actions = await actionsResponse.json();

        document.getElementById('total-actions').textContent =
          summary.totalActions;

        document.getElementById('active-users').textContent =
          summary.activeUsers;

        document.getElementById('notes-created').textContent =
          actionCount(summary, 'note_created');

        document.getElementById('notes-updated').textContent =
          actionCount(summary, 'note_updated');

        document.getElementById('notes-deleted').textContent =
          actionCount(summary, 'note_deleted')
          + actionCount(summary, 'note_purged');

        document.getElementById('workspace-changes').textContent =
          actionCount(summary, 'workspace_state_changed');

        renderBreakdown(summary.actionsByType ?? {});
        renderActions(actions);

        document.getElementById('updated').textContent =
          `Updated ${new Date().toLocaleString()}`;
      } catch {
        document.getElementById('updated').textContent =
          'Analytics temporarily unavailable.';
      }
    }

    function renderBreakdown(actionsByType) {
      const container = document.getElementById('breakdown');
      const entries = Object.entries(actionsByType);

      if (entries.length === 0) {
        container.innerHTML =
          '<div class="muted">No user actions yet.</div>';
        return;
      }

      container.innerHTML = entries
        .sort((left, right) => right[1] - left[1])
        .map(([action, count]) => `
          <article class="breakdown-item">
            <div class="breakdown-name">
              ${escapeHtml(readableAction(action))}
            </div>
            <div class="breakdown-count">
              ${escapeHtml(count)}
            </div>
          </article>
        `)
        .join('');
    }

    function renderActions(actions) {
      const body = document.getElementById('actions-body');

      if (!actions.length) {
        body.innerHTML = `
          <tr>
            <td colspan="3" class="muted">
              No user actions yet.
            </td>
          </tr>
        `;
        return;
      }

      body.innerHTML = actions
        .map(action => `
          <tr>
            <td class="mono">
              ${escapeHtml(
                new Date(action.timestampUtc).toLocaleString())}
            </td>

            <td class="mono">
              User ${escapeHtml(action.anonymizedUserId)}
            </td>

            <td>
              <span class="action">
                ${escapeHtml(readableAction(action.action))}
              </span>
            </td>
          </tr>
        `)
        .join('');
    }

    refreshAnalytics();
    setInterval(refreshAnalytics, 10_000);
  </script>
</body>
</html>
""";
}
