namespace Fasty.Api.Modules.Monitoring;

public static class UserDetailsDashboardPage
{
    public const string Html = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta
    name="viewport"
    content="width=device-width, initial-scale=1">

  <title>Fasty User Details</title>

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
      font-size: 1.15rem;
    }

    .subtitle,
    .muted {
      color: #777087;
    }

    .updated {
      margin: 5px 0 24px;
      color: #8b849d;
      font-size: 0.9rem;
    }

    .navigation {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin: 20px 0 28px;
    }

    .navigation a {
      padding: 9px 14px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.84);
      border: 1px solid rgba(80, 70, 120, 0.12);
      color: #514775;
      text-decoration: none;
      font-weight: 650;
    }

    .selector,
    .panel,
    .card {
      background: rgba(255, 255, 255, 0.86);
      border: 1px solid rgba(80, 70, 120, 0.12);
      box-shadow: 0 16px 45px rgba(78, 62, 125, 0.08);
      backdrop-filter: blur(16px);
    }

    .selector {
      border-radius: 22px;
      padding: 20px;
      margin-bottom: 20px;
    }

    label {
      display: block;
      margin-bottom: 8px;
      color: #6e6882;
      font-size: 0.86rem;
      font-weight: 700;
    }

    select {
      width: 100%;
      padding: 13px 14px;
      border: 1px solid rgba(80, 70, 120, 0.18);
      border-radius: 14px;
      background: white;
      color: #28243d;
      font: inherit;
    }

    .cards {
      display: grid;
      grid-template-columns:
        repeat(auto-fit, minmax(175px, 1fr));
      gap: 14px;
      margin-bottom: 22px;
    }

    .card {
      border-radius: 20px;
      padding: 18px;
    }

    .card-label {
      color: #777087;
      font-size: 0.82rem;
      font-weight: 650;
    }

    .card-value {
      margin-top: 7px;
      font-size: 1.7rem;
      font-weight: 780;
      letter-spacing: -0.035em;
    }

    .card-value.time {
      font-size: 1rem;
      letter-spacing: 0;
      line-height: 1.45;
    }

    .panel {
      border-radius: 24px;
      overflow: hidden;
      margin-bottom: 22px;
    }

    .panel-header {
      padding: 19px 21px;
      border-bottom: 1px solid rgba(80, 70, 120, 0.1);
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
      min-width: 650px;
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
      padding: 5px 9px;
      border-radius: 999px;
      background: #ece7ff;
      color: #504478;
      font-size: 0.82rem;
      font-weight: 700;
    }

    .hidden {
      display: none;
    }

    @media (max-width: 640px) {
      main {
        width: min(100% - 20px, 1180px);
        padding-top: 24px;
      }
    }
  </style>
</head>

<body>
  <main>
    <h1>Fasty User Details ✨</h1>

    <p class="subtitle">
      Per-user anonymized engagement metrics · no personal data
    </p>

    <p id="updated" class="updated">
      Loading…
    </p>

    <nav class="navigation">
      <a href="/monitoring">Operational monitoring</a>
      <a href="/monitoring/analytics">User analytics</a>
      <a href="/monitoring/users">User details</a>
    </nav>

    <section class="selector">
      <label for="user-select">
        Select anonymized user
      </label>

      <select id="user-select">
        <option value="">Loading users…</option>
      </select>
    </section>

    <section id="empty-state" class="panel">
      <div class="panel-header">
        <span class="muted">
          No tracked users yet.
        </span>
      </div>
    </section>

    <div id="user-content" class="hidden">
      <section class="cards">
        <article class="card">
          <div class="card-label">User</div>
          <div id="user-id" class="card-value">—</div>
        </article>

        <article class="card">
          <div class="card-label">Total actions</div>
          <div id="total-actions" class="card-value">—</div>
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

        <article class="card">
          <div class="card-label">Registrations</div>
          <div id="registrations" class="card-value">—</div>
        </article>

        <article class="card">
          <div class="card-label">Logins</div>
          <div id="logins" class="card-value">—</div>
        </article>

        <article class="card">
          <div class="card-label">Logouts</div>
          <div id="logouts" class="card-value">—</div>
        </article>

        <article class="card">
          <div class="card-label">Sessions revoked</div>
          <div id="sessions-revoked" class="card-value">—</div>
        </article>

        <article class="card">
          <div class="card-label">First activity</div>
          <div id="first-activity" class="card-value time">—</div>
        </article>

        <article class="card">
          <div class="card-label">Last activity</div>
          <div id="last-activity" class="card-value time">—</div>
        </article>
      </section>

      <section class="panel">
        <div class="panel-header">
          <h2>Action breakdown</h2>
        </div>

        <div id="breakdown" class="breakdown"></div>
      </section>

      <section class="panel">
        <div class="panel-header">
          <h2>Recent actions</h2>
        </div>

        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Local time</th>
                <th>Action</th>
              </tr>
            </thead>

            <tbody id="actions-body"></tbody>
          </table>
        </div>
      </section>
    </div>
  </main>

  <script>
    const select = document.getElementById('user-select');

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

    const count = (user, action) =>
      user.actionsByType?.[action] ?? 0;

    async function loadUsers() {
      const response = await fetch(
        '/monitoring/users/list',
        { cache: 'no-store' });

      if (!response.ok) {
        throw new Error('Unable to load users.');
      }

      const users = await response.json();

      if (!users.length) {
        select.innerHTML =
          '<option value="">No tracked users</option>';

        document.getElementById('empty-state')
          .classList.remove('hidden');

        document.getElementById('user-content')
          .classList.add('hidden');

        return;
      }

      const previousValue = select.value;

      select.innerHTML = users
        .map(user => `
          <option value="${escapeHtml(user.anonymizedUserId)}">
            User ${escapeHtml(user.anonymizedUserId)}
            · ${escapeHtml(user.totalActions)} actions
          </option>
        `)
        .join('');

      if (
        previousValue
        && users.some(
          user => user.anonymizedUserId === previousValue)
      ) {
        select.value = previousValue;
      }

      await loadSelectedUser();
    }

    async function loadSelectedUser() {
      const userId = select.value;

      if (!userId) {
        return;
      }

      const [userResponse, actionsResponse] =
        await Promise.all([
          fetch(
            `/monitoring/users/${encodeURIComponent(userId)}`,
            { cache: 'no-store' }),
          fetch(
            `/monitoring/users/${encodeURIComponent(userId)}/actions?limit=100`,
            { cache: 'no-store' })
        ]);

      if (!userResponse.ok || !actionsResponse.ok) {
        throw new Error('Unable to load user details.');
      }

      const user = await userResponse.json();
      const actions = await actionsResponse.json();

      document.getElementById('empty-state')
        .classList.add('hidden');

      document.getElementById('user-content')
        .classList.remove('hidden');

      document.getElementById('user-id').textContent =
        user.anonymizedUserId;

      document.getElementById('total-actions').textContent =
        user.totalActions;

      document.getElementById('notes-created').textContent =
        count(user, 'note_created');

      document.getElementById('notes-updated').textContent =
        count(user, 'note_updated');

      document.getElementById('notes-deleted').textContent =
        count(user, 'note_deleted')
        + count(user, 'note_purged');

      document.getElementById('workspace-changes').textContent =
        count(user, 'workspace_state_changed');

      document.getElementById('registrations').textContent =
        count(user, 'user_registered');

      document.getElementById('logins').textContent =
        count(user, 'user_logged_in');

      document.getElementById('logouts').textContent =
        count(user, 'user_logged_out');

      document.getElementById('sessions-revoked').textContent =
        count(user, 'session_revoked');

      document.getElementById('first-activity').textContent =
        new Date(user.firstActivityUtc).toLocaleString();

      document.getElementById('last-activity').textContent =
        new Date(user.lastActivityUtc).toLocaleString();

      renderBreakdown(user.actionsByType ?? {});
      renderActions(actions);

      document.getElementById('updated').textContent =
        `Updated ${new Date().toLocaleString()}`;
    }

    function renderBreakdown(actionsByType) {
      const entries = Object.entries(actionsByType);
      const container = document.getElementById('breakdown');

      container.innerHTML = entries.length
        ? entries
            .sort((left, right) => right[1] - left[1])
            .map(([action, actionCount]) => `
              <article class="breakdown-item">
                <div class="breakdown-name">
                  ${escapeHtml(readableAction(action))}
                </div>

                <div class="breakdown-count">
                  ${escapeHtml(actionCount)}
                </div>
              </article>
            `)
            .join('')
        : '<div class="muted">No actions.</div>';
    }

    function renderActions(actions) {
      const body = document.getElementById('actions-body');

      body.innerHTML = actions.length
        ? actions
            .map(action => `
              <tr>
                <td class="mono">
                  ${escapeHtml(
                    new Date(
                      action.timestampUtc).toLocaleString())}
                </td>

                <td>
                  <span class="action">
                    ${escapeHtml(
                      readableAction(action.action))}
                  </span>
                </td>
              </tr>
            `)
            .join('')
        : `
          <tr>
            <td colspan="2" class="muted">
              No actions.
            </td>
          </tr>
        `;
    }

    select.addEventListener(
      'change',
      loadSelectedUser);

    async function refresh() {
      try {
        await loadUsers();
      } catch {
        document.getElementById('updated').textContent =
          'User analytics temporarily unavailable.';
      }
    }

    refresh();
    setInterval(refresh, 10_000);
  </script>
</body>
</html>
""";
}
