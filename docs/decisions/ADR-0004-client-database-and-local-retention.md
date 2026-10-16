# ADR-0004 — Use SQLite with Drift for local note storage and separate attachment caching

- Status: Accepted
- Date: 2026-07-22
- Decision owners: Fasty maintainers

## Context

Fasty is a local-first application. Android, Windows, and web clients must remain useful when the server is unavailable or the device is offline.

The client therefore needs durable local storage for notes, synchronization state, pending operations, and conflict information. The storage model must work across Fasty's priority platforms while preserving a path to iOS, macOS, and Linux.

Storage pressure must also be considered. Text notes are usually small, but future attachments such as images, audio recordings, PDFs, and other documents may become large.

A suggestion was considered to remove local data after successful synchronization. This would reduce device storage usage, but deleting synchronized note text would break the local-first guarantee and make the application depend on the server for normal reading and search.

## Decision drivers

- Full offline access to note text
- Reliable local transactions for note changes and the synchronization outbox
- Type-safe queries and migrations in Dart
- Android, Windows, and web support
- Fast local search and note-list rendering
- Predictable recovery after application or network failure
- Controlled device storage usage
- Future support for media attachments
- Testability without requiring a live backend

## Considered options

1. SQLite with Drift across native and web clients
2. SQLite on native platforms with a separate IndexedDB implementation for web
3. Isar
4. Hive or another key-value/document store
5. Server-first storage with only temporary local caching
6. Delete all synchronized local content

## Decision

Fasty will use **SQLite with Drift** as its primary local persistence layer.

- Android, Windows, and other native clients will use SQLite through Drift.
- The web client will use Drift's WebAssembly SQLite backend, with browser persistence through available browser storage mechanisms.
- The local database will be the primary data source for the application UI.
- Network responses will be merged into the local database before becoming visible through the repository layer.
- Note text and synchronization metadata will remain stored locally after successful synchronization.
- Large attachment payloads will not be stored inside the main SQLite database.
- Attachment metadata will be stored locally, while binary content will use a separate file or browser-cache layer.
- Successfully uploaded attachment binaries may be evicted from local storage according to a configurable cache policy.
- An evicted attachment can be downloaded again from authoritative server storage when the user opens it.

## Local retention policy

Fasty will distinguish between **core offline data** and **re-downloadable binary data**.

### Core offline data — retained locally

The following remains on the device after synchronization:

- Note identifiers
- Note titles and textual content
- Creation and modification metadata
- Folders, tags, and pin state
- Deletion tombstones required by synchronization
- Current server version or synchronization cursor
- Pending outbox operations
- Conflict records that have not been resolved
- Attachment metadata and references

This data is retained because it is required for offline reading, editing, search, and reliable synchronization.

### Re-downloadable data — eligible for eviction

The following may be deleted locally only after the server confirms durable storage:

- Full-resolution images
- Audio recordings and voice notes
- Videos
- PDFs and office documents
- Other large binary attachments
- Generated previews that can be recreated

Eviction removes only the local cached binary. It does not delete the attachment record or server copy.

### User controls

A future storage-management feature should support:

- Keep all attachments offline
- Download attachments on demand
- Automatically remove cached attachments after a configurable period
- Clear attachment cache manually
- Pin selected notes or attachments for permanent offline availability
- Display local cache size and estimated reclaimable space

The default policy for the personal version will be conservative: note text always remains offline, while large attachments may be downloaded on demand after successful upload.

## Data ownership and source of truth

Fasty uses two related sources of truth:

- The local database is the immediate source of truth for the current client UI.
- The server is the authoritative shared source for synchronization between devices and recovery of synchronized data.

A local change is considered pending until the server confirms it. The local record must not be removed merely because a push request was sent; acknowledgement and synchronization state must be persisted transactionally.

## Local database responsibilities

The local database will contain tables or equivalent structures for:

- Notes
- Note revisions or conflict snapshots
- Folders and tags when introduced
- Attachment metadata
- Synchronization state
- Outbox operations
- Remote-change application state
- Device-local preferences that require structured persistence

Authentication tokens will not be stored in normal database tables. They require platform-appropriate secure storage and a separate security decision.

## Attachment architecture direction

Future attachment support will use a split model:

```text
Note record
    |
    +-- Attachment metadata in local SQLite
    |
    +-- Cached binary in device file storage or browser storage
    |
    +-- Authoritative binary in server object storage
```

The relational server database will store metadata such as:

- Attachment ID
- Owning note ID
- Owner ID
- File name
- Media type
- Size
- Content hash
- Upload state
- Storage object key
- Creation and deletion timestamps

Large binary content should be stored in object storage or a dedicated server file-storage abstraction rather than PostgreSQL rows.

## Web-specific considerations

Browser storage differs from native device storage:

- Browsers may enforce per-origin quotas.
- Data can be cleared by the user or browser policies.
- Persistence behavior varies by browser and browsing mode.
- Additional headers or worker assets may be needed for the preferred Drift WebAssembly backend.
- Web data must be treated as a durable convenience, not the only recovery copy after synchronization.

The web implementation must test:

- Persistence across browser restarts
- Behavior when storage quota is exhausted
- Behavior in private browsing modes
- Multi-tab database access
- Migration behavior
- Recovery after browser storage is cleared

## Consequences

### Positive

- Notes remain immediately available offline.
- The UI can observe a single local data source.
- Drift provides type-safe queries, transactions, migrations, and reactive streams.
- Native and web clients can share much of the persistence model.
- Note edits and outbox creation can occur in one local transaction.
- Text notes consume relatively little device storage.
- Large media can be managed through an independent cache policy.
- Future attachment support does not require storing large BLOBs in SQLite or PostgreSQL.

### Negative

- Every client maintains a local replicated data set.
- Database migrations must work across several platforms.
- Web persistence is more operationally complex than native SQLite.
- Attachment cache management introduces additional states and failure cases.
- Local search indexes and revision history may increase database size over time.

### Risks

- **Browser storage may be cleared or quota-limited.** Mitigation: synchronize durable data to the server, monitor quota errors, and provide clear recovery behavior.
- **A device may accumulate excessive media.** Mitigation: separate binary caching, configurable eviction, cache-size reporting, and on-demand downloads.
- **Cache eviction could remove an attachment that was not durably uploaded.** Mitigation: allow eviction only after server acknowledgement and integrity verification.
- **SQLite migrations could corrupt local state.** Mitigation: export schemas, test migrations from every supported version, back up critical state before destructive migrations, and rebuild synchronized data when safe.
- **Deleting synchronized note text could be reintroduced as an optimization.** Mitigation: treat full offline text as a product invariant; only explicitly classified re-downloadable binaries are evictable.

## Validation

Before considering this decision proven, the technical proof of concept must demonstrate:

1. Create and edit a note while offline.
2. Restart the application and retain the note.
3. Store a note change and an outbox operation atomically.
4. Synchronize the note and retain it locally afterwards.
5. Search synchronized notes while the backend is unavailable.
6. Run the same persistence model on Android, Windows, and web.
7. Apply and test a schema migration on all three priority platforms.
8. Simulate browser storage clearing and rebuild state from the server.
9. Upload a sample attachment, mark it durably synchronized, evict only its local binary, and download it again from the server.
10. Confirm that an unsynchronized attachment cannot be evicted automatically.

## Reconsideration triggers

Reconsider this decision if:

- Drift cannot provide sufficiently reliable support on one of the three priority platforms.
- Browser persistence limitations make the shared schema impractical.
- Local database performance is unacceptable with a representative note collection.
- End-to-end encryption introduces storage requirements incompatible with the chosen model.
- A future enterprise requirement mandates selective offline retention of note text.

## References

- Drift documentation: https://drift.simonbinder.eu/
- Drift web platform documentation: https://drift.simonbinder.eu/platforms/web/
- SQLite documentation: https://www.sqlite.org/docs.html
- SQLite limits: https://www.sqlite.org/limits.html
