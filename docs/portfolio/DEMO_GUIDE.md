# Fasty portfolio demo guide

This is a suggested **demo script**, not proof that any recording or screenshot has already been captured. The final media should be recorded only after the exact source snapshot has passed quality and security review.

## Keep demo data disposable

- Use a **local test backend** with an isolated PostgreSQL database, not the existing personal beta server.
- Create new fictional accounts and artificial notes (never a real email address, personal notebook, access token, Tailscale UI, or API credentials).
- Hide notifications, browser extensions, taskbar account details, home-directory paths, and device identifiers before recording.
- Don't show API configuration files or monitoring dashboards with actual account metrics.

## Suggested 60–90 second walkthrough

1. **Notes overview:** show the app on desktop and create a sample note with a short title.
2. **Visual workspace:** move or resize the card and link two sample notes.
3. **Markdown and tasks:** demonstrate a checklist and completed task rendering.
4. **Offline first:** disconnect the demo client from the test API, edit a note, and show it persists after restarting the app.
5. **Synchronization:** reconnect, synchronize, and display the changed note from a second *separately configured* client.
6. **Organization:** briefly show note search, pinning, and Trash/restore.
7. **Close:** show the architecture overview (Flutter + Drift → ASP.NET Core → PostgreSQL).

**Be precise:** an offline demo shows queued local writes and recovery; it does not prove conflict-free merges. The current conflict policy is last-write-wins.

## Recommended media for a GitHub README

- `screenshots/desktop-workspace.png` — visual canvas with fictional notes
- `screenshots/mobile-notes.png` — mobile card layout (no private notifications)
- `screenshots/markdown-checklist.png` — task editing and checked state
- `screenshots/sync-status.png` — UI explaining pending/retried changes, with no private content
- An optional short GIF or video of an offline edit that later reaches a second client

These filenames are **proposals only**; don't add broken README image links until the files exist. Do not copy UI images from third-party notes applications.

## Technical verification

Before recording, capture the commit SHA, Flutter and .NET SDK versions, and results of the documented test commands. Avoid claiming mobile or web platforms were validated if only a compile smoke test ran.

For a portfolio review, a truthful limitations section is more valuable than claiming full production readiness.
