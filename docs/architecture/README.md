# Architecture Documentation

This directory contains both the long-term technical direction and documents that describe the currently implemented personal alpha.

## Current documents

- [`c4-diagrams.md`](c4-diagrams.md) — intended system context, containers, backend modules, client synchronization components, sequence, and deployment views
- [`data-model.md`](data-model.md) — intended entities, ownership, identifiers, versions, synchronization records, conflicts, tombstones, and attachments
- [`synchronization.md`](synchronization.md) — implemented note/workspace synchronization behavior, guarantees, retry rules, automated coverage, and known limitations

When an intended architecture document differs from the current code, `synchronization.md`, source code, migrations, and passing tests are the source of truth for current behavior.

## Architecture decisions

Accepted technology and design choices are recorded in [`../decisions/README.md`](../decisions/README.md).

The current foundation establishes:

- Flutter for Android, Windows, web, and future supported clients;
- ASP.NET Core on .NET 10;
- PostgreSQL as the authoritative server database;
- SQLite with Drift as local persistence;
- an outbox-based local-first note synchronization path;
- REST for durable synchronization;
- a modular-monolith backend direction;
- Docker Compose and private Tailscale access for personal deployment.

The following remain planned rather than implemented:

- SignalR changes-available notifications;
- object storage and attachments;
- ASP.NET Core Identity and per-user authorization;
- server revisions/change feed;
- conflict-free or operation-based workspace synchronization;
- secure platform session storage.

## Documentation rules

- Diagrams are stored as text using Mermaid.
- Architecture documents distinguish implemented behavior from future design.
- Significant choices link to an Architecture Decision Record.
- Synchronization and security invariants must be updated whenever implementation changes them.
- Every synchronization bug fix requires a regression test.
- Material departures from an accepted ADR require updating or superseding that ADR.
