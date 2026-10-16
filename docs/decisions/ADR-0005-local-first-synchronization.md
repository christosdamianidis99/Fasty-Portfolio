# ADR-0005 — Use an outbox-based local-first synchronization protocol

- Status: Accepted
- Date: 2026-07-22
- Decision owners: Fasty maintainers

## Context

Fasty must allow users to create, edit, delete, search, and read notes while offline. Changes made on one device must later synchronize safely to the server and other devices without duplication or silent data loss.

The system must tolerate:

- Intermittent connectivity
- Application restarts
- Device sleep and process termination
- Requests timing out after the server has already committed them
- Duplicate retries
- Devices remaining offline for extended periods
- Concurrent edits to the same note
- Deletions that must propagate to devices that were offline
- A temporarily unavailable backend

A direct request-response CRUD design is insufficient because it couples user actions to network availability and cannot safely represent pending changes.

## Decision drivers

- Offline usability
- Immediate local save behavior
- Retry safety and idempotency
- Incremental synchronization
- Conflict detection and content preservation
- Clear server authority without making the server necessary for every interaction
- Testability under failure conditions
- Compatibility with Android, Windows, and web
- A future path toward attachments, sharing, and enterprise auditability

## Considered options

1. Network-first CRUD with a local cache
2. Periodic full-state upload and download
3. Database replication between SQLite and PostgreSQL
4. Event sourcing for every client and server operation
5. Local-first synchronization using a client outbox and server change feed

## Decision

Fasty will use an application-controlled, local-first synchronization protocol based on:

- A local SQLite database as the client source of truth for the user interface
- A transactional client outbox containing pending operations
- Idempotent push operations identified by a globally unique client operation ID
- An authoritative server database in PostgreSQL
- A server-generated, monotonically increasing synchronization cursor
- An incremental pull endpoint that returns changes after a client's last acknowledged cursor
- Tombstones for deletions
- Optimistic concurrency checks for updates
- Explicit conflict records that preserve both versions when automatic resolution is unsafe
- Optional real-time notifications that trigger synchronization but do not carry authoritative state

The client will normally perform a synchronization cycle in this order:

1. Read pending outbox operations.
2. Push a bounded batch to the server.
3. Receive per-operation acknowledgements or conflict results.
4. Mark acknowledged outbox entries as completed in a local transaction.
5. Pull server changes after the local synchronization cursor.
6. Apply the returned changes and advance the cursor atomically.
7. Repeat while more work remains, subject to backoff and cancellation.

The protocol must remain correct if push and pull are repeated.

## Client write path

When a user edits a note, Fasty will not wait for the network.

The client will atomically:

1. Update the note in SQLite.
2. Increment or replace its local pending state.
3. Add an operation to the outbox.

Only after the local transaction commits will the interface report that the note is saved locally.

A later synchronization worker sends the operation to the backend.

## Client outbox

Each outbox entry will include at least:

- `operationId`: UUID generated once by the client
- `deviceId`: stable identifier for the installation
- `entityType`
- `entityId`
- `operationType`: create, update, or delete
- `baseServerVersion`: server version on which the local edit was based
- `payload` or sufficient changed data
- `createdAt`
- `attemptCount`
- `nextAttemptAt`
- `state`: pending, in-flight, acknowledged, conflict, or permanently failed

Retries must reuse the same `operationId`. Creating a new ID for every retry would defeat idempotency.

Multiple unsent edits to the same note may later be compacted into one effective operation, provided compaction preserves the correct base version and never discards a required delete or conflict state.

## Server push processing

For each operation, the server will:

1. Authenticate the user and authorize access to the entity.
2. Check whether the `operationId` was already processed.
3. If already processed, return the stored result without applying the operation again.
4. Validate the operation and its expected base version.
5. Apply the domain change, create the synchronization change record, and persist the processed-operation result in one database transaction.
6. Return the authoritative entity version and synchronization cursor.

The note mutation and corresponding durable change record must commit atomically. A server response is not the source of durability; the committed PostgreSQL transaction is.

## Server change feed

The server will maintain a durable ordered change feed scoped to the authenticated user or future tenant.

A client will request changes using a cursor, conceptually:

```http
GET /api/sync/changes?after=1842&limit=500
```

The response will contain:

- Ordered changes after cursor `1842`
- The cursor represented by the last returned change
- A flag indicating whether more changes are available
- Current server time for diagnostics only

The cursor will be server-generated and monotonic. Client timestamps will not determine synchronization order because clocks can drift or be incorrect.

The change feed may initially use a database sequence or ordered change-table identifier. Its retention policy must guarantee that supported clients can reconnect after the documented maximum offline period. If historical changes are compacted, the protocol must support a safe full resynchronization.

## Applying pulled changes

The client will apply one page of remote changes and update its local cursor in the same SQLite transaction.

If the application crashes before commit, the page will be downloaded and applied again. Therefore, applying a change must be idempotent by entity version and change identifier.

Remote changes will be written to SQLite before the interface observes them.

## Deletions

Deleting a note will create a tombstone instead of immediately erasing every trace of the entity.

The tombstone will contain enough information to propagate deletion to offline devices, including:

- Entity ID
- Owner or tenant scope
- Deletion server version
- Change cursor
- Deletion time

Clients will mark the local entity as deleted and hide it from normal views while retaining the state necessary for synchronization and optional restoration.

Tombstones may be physically removed only under a documented retention policy that accounts for long-offline devices, backups, restore behavior, and future compliance requirements.

## Conflict detection

Every synchronized note will have a server-managed version.

An update includes the `baseServerVersion` observed when the local edit began. If the current server version differs, the server detects a conflict rather than blindly overwriting newer content.

For the first version, Fasty will use the following strategy:

- Non-overlapping metadata changes may be merged only when explicitly proven safe.
- Concurrent text-content edits will not be silently merged.
- The server will preserve the current server version and the submitted client version.
- A conflict record will be returned and stored locally.
- The user can select, copy, or manually merge the versions.
- No content version involved in a detected conflict will be deleted automatically.

Last-write-wins based solely on device timestamps is rejected because it can silently lose content and depends on unreliable clocks.

## Acknowledgements and local cleanup

An outbox operation may be removed or archived only after the client receives an acknowledgement that can be matched to the same `operationId` and the acknowledgement is committed locally.

Text notes and searchable metadata remain in local SQLite after synchronization to preserve offline access.

Large attachment binaries follow a separate cache policy. A local attachment may become eligible for eviction only after the server confirms durable storage and integrity verification, while its metadata remains local.

## Scheduling and triggers

Synchronization may be triggered by:

- Application startup
- A local write
- Network reconnection
- Returning to the foreground
- A user-initiated refresh
- A bounded periodic timer
- A server notification such as SignalR

Only one synchronization coordinator should process a user account at a time within a client installation. Triggers should coalesce rather than start overlapping synchronization loops.

The worker must support cancellation and exponential backoff with jitter for transient failures. Authentication failures, validation errors, conflicts, and permanent failures must not be retried indefinitely as if they were network errors.

ASP.NET Core hosted services may be used for server-side background work, but correctness must not depend on graceful process shutdown or in-memory queues. Durable work must be represented in persistent storage before returning success.

## API shape

The exact contract will be specified separately, but the synchronization API will conceptually include:

```text
POST /api/sync/push
GET  /api/sync/changes
POST /api/sync/bootstrap
```

`push` accepts bounded batches of idempotent operations.

`changes` returns incremental authoritative changes after a cursor.

`bootstrap` supports first installation, local database reconstruction, or recovery when the client's cursor is older than retained change history.

The API will use explicit versioning and bounded request/response sizes.

## Data model implications

The backend will require structures equivalent to:

- Notes with server versions
- Durable change-feed records
- Processed client operations and stored results
- Device registrations or installation identifiers
- Conflict records or preserved revisions
- Deletion tombstones

The client will require:

- Notes and metadata
- Outbox operations
- Synchronization state and cursor
- Conflict records
- Device identity
- Attachment metadata and cache state

## Consistency model

Fasty provides immediate local consistency on one device and eventual convergence across devices when communication resumes and conflicts are resolved.

The server is authoritative for accepted shared state and ordering, but the local database is authoritative for what the current user interface displays and for unsynchronized local work.

The system does not promise that two offline devices immediately show identical state.

## Consequences

### Positive

- Users can work without network access.
- Local writes are fast and durable.
- Retries do not duplicate accepted operations.
- Synchronization transfers only pending operations and incremental changes.
- Deletions propagate to offline devices.
- Conflicting edits are detected and preserved.
- The protocol does not depend on client clock accuracy.
- Real-time notifications remain an optimization rather than a correctness dependency.
- The design can later support additional synchronized entities.

### Negative

- Considerably more complexity than ordinary CRUD.
- Both client and server require synchronization-specific tables and logic.
- Schema and protocol evolution require careful compatibility testing.
- Tombstone and change-feed retention create operational responsibilities.
- Conflict user experience must be designed.
- Browser lifecycle restrictions make background synchronization less predictable.

### Risks and mitigations

- **Outbox corruption or loss:** use SQLite transactions, migrations, integrity checks, and tests that kill the process at failure points.
- **Duplicate processing:** enforce unique operation IDs on the server and store the original result.
- **Cursor advanced without data:** apply remote changes and cursor advancement in one transaction.
- **Infinite retry loops:** classify failures and apply bounded backoff, visibility, and manual recovery.
- **Tombstones removed too early:** define and test an explicit retention and bootstrap policy.
- **Large change feeds:** paginate, index by owner and cursor, compact safely, and monitor growth.
- **Schema mismatch:** version API contracts and support migrations before dropping old fields.
- **Concurrent client sync loops:** serialize them with a coordinator or lock per account.
- **Server accepted operation but response was lost:** retry with the same operation ID and return the stored result.
- **Attachment data loss after cache eviction:** require server acknowledgement and content-hash verification before eviction eligibility.

## Validation

Before Phase 2 is complete, automated integration and end-to-end tests must demonstrate at least:

1. Create a note offline, restart the client, reconnect, and synchronize it.
2. Edit the same note several times offline and converge without duplicate notes.
3. Delete a note while another device is offline and propagate the tombstone later.
4. Simulate a timeout after the server commits, retry the same operation, and verify one mutation.
5. Crash the client after downloading changes but before committing them, then recover safely.
6. Crash after applying changes but before the cursor transaction would otherwise complete, ensuring atomic behavior.
7. Edit the same note independently on two devices and preserve both versions as a conflict.
8. Synchronize more changes than fit in one page.
9. Reconstruct a fresh client using bootstrap.
10. Recover when a cursor is older than retained change history.
11. Run repeated triggers concurrently and verify only one effective synchronization loop.
12. Keep local notes accessible during a backend outage.
13. Verify that attachment cache eviction is impossible before durable upload acknowledgement and integrity validation.

Fault-injection tests are required because happy-path tests cannot establish synchronization reliability.

## Reconsideration triggers

Revisit this decision if:

- Fasty introduces real-time collaborative character-level editing.
- A mature synchronization engine or CRDT framework demonstrably reduces complexity without compromising platform support and data ownership.
- The product requires peer-to-peer synchronization without a central server.
- Enterprise requirements demand a fundamentally different consistency or retention model.

## References

- Microsoft documentation: EF Core transactions and optimistic concurrency
- PostgreSQL documentation: transactions and isolation
- SQLite documentation: transactions and atomic commit
- Microsoft documentation: ASP.NET Core hosted services and background tasks
