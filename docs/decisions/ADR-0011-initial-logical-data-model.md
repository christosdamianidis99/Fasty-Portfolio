# ADR-0011 — Initial logical data model

- Status: Accepted
- Date: 2026-07-23
- Decision owners: Fasty maintainers

## Context

Fasty needs a stable starting model before backend and client scaffolding begins. The model must support multiple devices, local-first synchronization, idempotent retries, conflict preservation, deletion tombstones, secure device sessions, and future attachments without prematurely introducing collaboration or enterprise complexity.

## Decision drivers

- Correct synchronization transaction boundaries
- Clear ownership and authorization rules
- PostgreSQL relational integrity
- Compatibility with SQLite client persistence
- Extensibility without speculative complexity
- Explicit separation of metadata from binary attachment storage

## Considered options

1. Relational entities with explicit synchronization records and versions
2. A single generic JSON document table
3. Event sourcing as the primary persistence model
4. Separate databases per module from the first release
5. A minimal notes-only table with synchronization added later

## Decision

Adopt the logical model documented in [`../architecture/data-model.md`](../architecture/data-model.md).

The initial authoritative entities are:

- User
- Device
- DeviceSession
- Note
- SyncOperation
- ChangeEntry
- DeviceSyncState
- NoteConflict
- Attachment

The local client adds operational tables for local notes, attachment metadata, outbox operations, synchronization metadata, conflict copies, and attachment cache state.

### Core invariants

- Every user-owned resource is filtered and authorized by the authenticated user.
- External identifiers use UUIDs.
- Server ordering uses a monotonic change cursor, never device clocks.
- Each mutable synchronized entity has a server-managed version.
- A local mutation and outbox operation commit atomically in SQLite.
- An accepted server mutation, idempotency record, and change entry commit atomically in PostgreSQL.
- Duplicate operation IDs return the original committed result.
- Stale writes preserve both server and client snapshots through a conflict record.
- Deletions remain as tombstones until retention cleanup is safe.
- Attachment binaries remain outside PostgreSQL; PostgreSQL stores their metadata and lifecycle state.

### Deferred model areas

The MVP does not yet model organizations, sharing, tags, folders, rich-text blocks, comments, reminders, billing, AI embeddings, or collaboration. These require explicit future requirements and migrations.

## Consequences

### Positive

- Synchronization requirements are reflected directly in persistence.
- Database constraints can protect ownership and idempotency.
- Client and server responsibilities are explicit.
- The model supports future attachments without storing large binaries in PostgreSQL.
- Deferred features do not complicate the first implementation.

### Negative

- Synchronization introduces more tables than a simple CRUD notes application.
- Client and server schemas require coordinated migrations.
- Tombstones and idempotency records require retention policies.
- Conflict records add user-interface and operational work.

### Risks

- The model may be over-generalized before implementation. Mitigation: create only fields required by Phase 1 and Phase 2, while preserving documented invariants.
- Change-feed growth may become significant. Mitigation: measure usage and design retention/bootstrap rules before cleanup.
- EF Core mappings could accidentally expose infrastructure entities. Mitigation: map API contracts explicitly and test module boundaries.

## Validation

Before Phase 2 completion, tests must demonstrate:

1. A note mutation and change entry cannot commit independently.
2. Duplicate operation IDs do not duplicate mutations.
3. One user cannot query another user's entities.
4. A stale note update produces a preserved conflict.
5. A deletion is propagated to a device that was offline.
6. A fresh device can bootstrap and then continue incrementally.
7. Attachment metadata cannot reference a note owned by another user.
8. Client cursor advancement rolls back when applying a change page fails.
