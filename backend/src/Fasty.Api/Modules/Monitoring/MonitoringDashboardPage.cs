namespace Fasty.Api.Modules.Monitoring;

public static class MonitoringDashboardPage
{
    public static string Render()
    {
        return """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Fasty Monitoring</title>
  <style>
    :root {
      --bg: #fffafc;
      --panel: #ffffff;
      --panel-2: #fff3f8;
      --text: #2d2430;
      --muted: #7a6d78;
      --border: #f1d9e5;
      --accent: #e88ab1;
      --accent-2: #a98cf0;
      --good: #3aa675;
      --shadow: 0 10px 30px rgba(232, 138, 177, 0.10);
      --radius: 20px;
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background:
        radial-gradient(circle at top left, #ffe7f1 0, transparent 28%),
        radial-gradient(circle at top right, #efe6ff 0, transparent 24%),
        var(--bg);
      color: var(--text);
    }

    .wrap {
      max-width: 1100px;
      margin: 0 auto;
      padding: 24px;
    }

    .hero {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 16px;
      margin-bottom: 22px;
      padding: 22px;
      background: linear-gradient(135deg, #fff7fb, #f8f3ff);
      border: 1px solid var(--border);
      border-radius: 24px;
      box-shadow: var(--shadow);
    }

    .title {
      margin: 0;
      font-size: 28px;
      font-weight: 800;
      letter-spacing: -0.02em;
    }

    .subtitle {
      margin-top: 6px;
      color: var(--muted);
      font-size: 14px;
    }

    .pill {
      background: #ffffffcc;
      border: 1px solid var(--border);
      border-radius: 999px;
      padding: 10px 14px;
      font-size: 13px;
      color: var(--muted);
      white-space: nowrap;
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 16px;
      margin-bottom: 18px;
    }

    .card {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
      padding: 18px;
    }

    .card.soft {
      background: var(--panel-2);
    }

    .label {
      color: var(--muted);
      font-size: 13px;
      margin-bottom: 8px;
    }

    .value {
      font-size: 28px;
      font-weight: 800;
      letter-spacing: -0.03em;
    }

    .small {
      margin-top: 6px;
      color: var(--muted);
      font-size: 12px;
    }

    .section {
      margin-top: 16px;
    }

    .section-head {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 12px;
    }

    .section-title {
      margin: 0;
      font-size: 18px;
      font-weight: 700;
    }

    .table-wrap {
      overflow: auto;
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
    }

    table {
      width: 100%;
      border-collapse: collapse;
      min-width: 760px;
    }

    th, td {
      padding: 14px 16px;
      text-align: left;
      border-bottom: 1px solid #f7e6ee;
      font-size: 14px;
      vertical-align: top;
    }

    th {
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      background: #fffafd;
      position: sticky;
      top: 0;
    }

    tr:last-child td {
      border-bottom: none;
    }

    .status {
      display: inline-block;
      border-radius: 999px;
      padding: 4px 10px;
      font-size: 12px;
      font-weight: 700;
      background: #eefbf4;
      color: var(--good);
    }

    .status.fail {
      background: #fff1f4;
      color: #c25578;
    }

    .mono {
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 12px;
    }

    .muted {
      color: var(--muted);
    }

    @media (max-width: 900px) {
      .grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .hero {
        flex-direction: column;
        align-items: flex-start;
      }
    }

    @media (max-width: 560px) {
      .grid {
        grid-template-columns: 1fr;
      }

      .wrap {
        padding: 16px;
      }

      .title {
        font-size: 24px;
      }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <section class="hero">
      <div>
        <h1 class="title">Fasty Monitoring ✨</h1>
        <div class="subtitle">
          Private beta operational dashboard · metadata only · no user content
        </div>
      </div>
      <div class="pill" id="lastUpdated">Refreshing…</div>
    </section>

    <section class="grid">
      <div class="card soft">
        <div class="label">Stored requests</div>
        <div class="value" id="storedRequests">—</div>
        <div class="small">Recent in-memory samples</div>
      </div>

      <div class="card">
        <div class="label">Active requests</div>
        <div class="value" id="activeRequests">—</div>
        <div class="small">Current in-flight requests</div>
      </div>

      <div class="card soft">
        <div class="label">Failed requests</div>
        <div class="value" id="failedRequests">—</div>
        <div class="small">Server-side failures only</div>
      </div>

      <div class="card">
        <div class="label">Avg duration</div>
        <div class="value" id="averageDuration">—</div>
        <div class="small">Milliseconds</div>
      </div>
    </section>

    <section class="section">
      <div class="section-head">
        <h2 class="section-title">Recent requests</h2>
        <div class="pill">Auto-refresh every 10s</div>
      </div>

      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Time (UTC)</th>
              <th>Method</th>
              <th>Route</th>
              <th>User</th>
              <th>Status</th>
              <th>Duration</th>
              <th>Result</th>
            </tr>
          </thead>
          <tbody id="requestsTable">
            <tr>
              <td colspan="7" class="muted">Loading…</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>

  <script>
    async function loadDashboard() {
      const [summaryResponse, requestsResponse] = await Promise.all([
        fetch('/monitoring/summary', { cache: 'no-store' }),
        fetch('/monitoring/requests?limit=20', { cache: 'no-store' })
      ]);

      if (!summaryResponse.ok || !requestsResponse.ok) {
        throw new Error('Failed to load monitoring data.');
      }

      const summary = await summaryResponse.json();
      const requests = await requestsResponse.json();

      document.getElementById('storedRequests').textContent = summary.storedRequests;
      document.getElementById('activeRequests').textContent = summary.activeRequests;
      document.getElementById('failedRequests').textContent = summary.failedRequests;
      document.getElementById('averageDuration').textContent =
        Number(summary.averageDurationMilliseconds).toFixed(1);

      document.getElementById('lastUpdated').textContent =
        'Updated ' + new Date(summary.generatedAtUtc).toLocaleString();

      const body = document.getElementById('requestsTable');

      if (!requests.length) {
        body.innerHTML = '<tr><td colspan="7" class="muted">No requests yet.</td></tr>';
        return;
      }

      body.innerHTML = requests.map(request => {
        const failed = request.failed === true;
        const statusClass = failed ? 'status fail' : 'status';
        const statusText = failed ? 'Failed' : 'OK';

        return `
          <tr>
            <td class="mono">${escapeHtml(request.timestampUtc)}</td>
            <td>${escapeHtml(request.method)}</td>
            <td class="mono">${escapeHtml(request.route)}</td>
            <td class="mono">${
              request.anonymizedUserId
                ? 'User ' + escapeHtml(request.anonymizedUserId)
                : 'Anonymous'
            }</td>
            <td>${escapeHtml(String(request.statusCode))}</td>
            <td>${Number(request.durationMilliseconds).toFixed(1)} ms</td>
            <td><span class="${statusClass}">${statusText}</span></td>
          </tr>
        `;
      }).join('');
    }

    function escapeHtml(value) {
      return String(value)
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    }

    async function refresh() {
      try {
        await loadDashboard();
      } catch (error) {
        document.getElementById('lastUpdated').textContent =
          'Refresh failed';
      }
    }

    refresh();
    setInterval(refresh, 10000);
  </script>
</body>
</html>
""";
    }
}
