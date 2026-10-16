# Fasty — engineering portfolio highlights

Fasty is an **offline-first, cross-platform notes and visual workspace application** built as an independent full-stack engineering project.

## Highlights

**Cross-platform client.** Flutter/Dart shares core notes, identity, and synchronization behavior between desktop and mobile; desktop supports spatial note placement and directed connections, while mobile uses card-based organization.

**Durable local-first behavior.** SQLite/Drift persists notes and queued mutations independently of the server. The client supports offline editing, retryable synchronization, soft deletion, restoration, and local restart behavior.

**Backend and identity.** ASP.NET Core (.NET 10) provides REST endpoints backed by EF Core/PostgreSQL. The private beta implemented registration, authenticated user ownership, refresh sessions, Google identity integration, and short-lived admin-assisted recovery.

**Engineering practices.** Explicit architecture decision records, automated widget and integration tests, PostgreSQL-backed backend tests, Docker Compose, and CI build checks demonstrate an emphasis on repeatability and evidence.

## Trade-offs and lessons

- **Last-write-wins vs collaboration:** a practical approach for a personal beta, but not suitable for lossless concurrent editing; a future collaboration product would require more sophisticated conflict tracking.
- **Offline-first complexity:** explicit pending operations, retries, tombstones, and local durability matter more than optimistic network-only CRUD.
- **Security boundaries:** private network access does not replace application authorization; secrets and recovery administration require separate controls.
- **Release discipline:** a test passing in CI does not prove a complete native-device and backup/restore acceptance matrix.

## Evidence, not marketing claims

The historical R3 follow-up recorded **226 Flutter tests passing** and **164 backend tests passing** at an earlier checkpoint, alongside a Linux debug build. These are historical checkpoints, not guaranteed results for every later commit. Check GitHub Actions for results on the exact branch.

See the [R3 summary](../R3_CHECKPOINT_2026-09-30.md), [architecture](../architecture/README.md), and [synchronization details](../architecture/synchronization.md).

## CV-ready description

> Developed Fasty, an offline-first cross-platform notes application using Flutter, SQLite/Drift, ASP.NET Core (.NET 10), and PostgreSQL. Implemented offline data persistence, cross-device synchronization, JWT/refresh-session authentication, visual workspaces, and automated regression and API integration testing.
