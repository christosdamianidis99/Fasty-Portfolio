# ADR-0009 — Attachment and object-storage architecture

- Status: Accepted
- Date: 2026-07-23
- Decision owners: Fasty maintainers

## Context

Fasty will initially focus on text notes, but the product roadmap includes images, voice recordings, PDFs, office documents, and other files. Binary media has different storage, synchronization, caching, integrity, and backup requirements from note text.

Attachments must work across Android, Windows, and web; tolerate interrupted uploads; remain recoverable after local eviction; and migrate from a personal Lubuntu deployment to cloud object storage without changing product behaviour.

## Decision drivers

- Preserve user data during interrupted uploads and retries.
- Avoid storing large binary objects in normal PostgreSQL rows.
- Allow local media eviction after durable upload verification.
- Support future S3-compatible storage.
- Keep attachment metadata synchronized through the existing change feed.
- Support mobile and browser memory constraints.
- Provide secure, authorized downloads.
- Prepare for thumbnails, audio metadata, and media processing.
- Keep the first implementation simple enough for one developer.

## Considered options

1. Store binary data directly in PostgreSQL.
2. Store binaries on the API host filesystem only.
3. Use object storage with PostgreSQL metadata.
4. Embed media directly inside note content.

## Decision

Fasty will store attachment metadata in PostgreSQL and binary content in a storage abstraction that supports a local filesystem implementation for personal deployment and an S3-compatible implementation for future hosted environments.

```text
Note
 └── Attachment metadata → PostgreSQL + sync feed
      └── Binary object → object storage abstraction
           ├── Personal phase: protected local storage volume
           └── Hosted phase: S3-compatible object storage
```

Large binary content will not be embedded in note records or normal synchronization payloads.

## Attachment lifecycle

An attachment will move through explicit states:

```text
LocalPending
  → Uploading
  → UploadedUnverified
  → Available
  → Deleted
  → Purged
```

Failed uploads remain retryable. A local source file must not become eligible for eviction until the attachment reaches `Available` and the client commits that acknowledgement locally.

## Initial metadata

The server-side attachment model should support at least:

- `AttachmentId`
- `NoteId`
- `OwnerId`
- `OriginalFileName`
- `MediaType`
- `SizeBytes`
- `ContentHash`
- `StorageObjectKey`
- `UploadState`
- `CreatedAtUtc`
- `UpdatedAtUtc`
- `DeletedAtUtc`
- `ServerVersion`
- optional image dimensions
- optional audio duration
- optional preview or thumbnail reference

The database stores metadata and ownership. The object key is internal and must not be treated as a public URL.

## Upload protocol

The first implementation may use authenticated API-mediated uploads for simplicity, with strict file-size limits and streaming rather than buffering entire files in memory.

The long-term design may use short-lived, narrowly scoped pre-signed upload URLs when an S3-compatible provider is introduced.

The upload sequence is:

1. Client creates an attachment metadata record with a stable attachment ID and operation ID.
2. Server validates ownership, media type, size limits, and quota.
3. Client uploads the binary using a retryable upload session.
4. Server or storage provider calculates or verifies size and content hash.
5. Server marks the attachment `Available` and emits a durable synchronization change.
6. Client pulls or receives the acknowledgement and stores it locally.
7. The original local binary becomes eligible for cache eviction according to user policy.

For small MVP files, a single streaming upload request is acceptable. Resumable multipart uploads become mandatory before supporting large audio, video, or document files.

## Integrity

Fasty will use a cryptographic content hash, initially SHA-256, to verify upload integrity.

A successful HTTP response alone is insufficient to permit local deletion. The authoritative attachment record must confirm:

- expected attachment ID
- expected byte length
- matching content hash
- durable available state

Hash equality may later support deduplication, but deduplication is not an initial requirement because it introduces privacy, authorization, and reference-counting complexity.

## Download and authorization

Every attachment download must be authorized against the authenticated user and note ownership.

The API may either stream the object or issue a short-lived signed download URL. Permanent public object URLs are prohibited.

Downloaded files must be treated as untrusted content. Fasty must set safe content-disposition headers, avoid inline execution of dangerous formats, and apply file-type validation.

## Local caching and eviction

Attachment metadata remains in the local SQLite database. Binary content is stored in a separate cache or user-selected offline storage area.

Supported future retention policies include:

- Keep all attachments offline.
- Download attachments on demand.
- Keep attachments for pinned notes offline.
- Evict cached attachments after a configurable period.
- Clear media cache manually.
- Display used and reclaimable storage.

Cache eviction removes only the local binary copy. It must not create a server deletion operation.

Unsynchronized, failed, or unverified uploads are never automatically evicted.

## Offline behaviour

A cached attachment can be opened offline. An uncached attachment displays its metadata and an unavailable-offline state.

Creating an attachment offline is supported by retaining the local source and adding a durable upload operation to the outbox. The upload begins when connectivity returns.

## Deletion

Deleting an attachment creates a synchronized tombstone. The metadata record is logically deleted first, while the binary object is physically removed only after a retention period or cleanup policy.

This delay supports offline devices, recovery from accidental deletion, and safe retry handling.

Object cleanup must be idempotent. Missing objects during cleanup are treated as already removed rather than fatal errors.

## Media processing

Thumbnail generation, image resizing, waveform generation, document previewing, transcription, and virus scanning are not part of the first attachment implementation.

The architecture must permit these processes to be added later as asynchronous jobs. Original uploads must remain immutable; derived previews are stored as separate objects.

## Storage abstraction

Application code will depend on an attachment storage interface rather than local paths or a specific cloud SDK.

Expected capabilities include:

- create or begin upload
- write or complete upload
- open authorized read stream
- verify object metadata
- delete object idempotently
- check existence for diagnostics

The abstraction must remain small and model Fasty requirements rather than expose every provider feature.

## Personal deployment

The Lubuntu deployment may use a Docker-managed or bind-mounted protected directory as the binary store.

Requirements:

- The directory is not served directly by the web server.
- Only the Fasty API and backup process can access it.
- Object keys are generated identifiers, not user-provided paths.
- Backups include both PostgreSQL metadata and binary objects.
- Restore procedures verify consistency between metadata and stored objects.

## Hosted deployment

The hosted version will prefer S3-compatible object storage. Migration must preserve attachment IDs, metadata, hashes, and object keys or perform a controlled key rewrite.

The application must not assume AWS specifically; provider-specific details remain inside infrastructure code.

## Limits and quotas

Before public release, Fasty must define:

- allowed media types
- maximum file size
- per-account storage quota
- upload rate limits
- retention for deleted objects
- timeout and multipart thresholds

The personal phase may begin with conservative fixed limits.

## Security

- Filenames are display metadata only and never filesystem paths.
- Object keys use generated values.
- Upload and download endpoints require authentication and authorization.
- MIME type claims are validated against content where practical.
- Executable or dangerous formats may be rejected or forced to download.
- Logs never contain binary content or signed URLs.
- Signed URLs, when introduced, are short lived and operation specific.
- Storage credentials remain outside source control.

## Backup and recovery

Database and binary backups must be coordinated enough to recover a consistent system.

The restore process must detect:

- metadata with missing objects
- unreferenced stored objects
- hash or size mismatches
- incomplete uploads

A periodic reconciliation job may report and later repair these conditions.

## Consequences

### Positive

- Note synchronization remains lightweight.
- Large media can be cached and evicted independently.
- Personal and hosted storage use the same application contract.
- Upload integrity is explicitly verified.
- PostgreSQL remains focused on transactional metadata.
- Future media processing can be added without redesigning note storage.

### Negative

- Backups now cover two data stores.
- Upload state management is more complex than ordinary note synchronization.
- Browser and mobile platforms require platform-specific file handling.
- Large-file resumability requires later protocol work.
- Object cleanup and metadata reconciliation require operational jobs.

### Risks

- **Database/object inconsistency:** mitigate with explicit states, hashes, reconciliation, and tested restores.
- **Local data loss before upload:** never evict unacknowledged media.
- **Unauthorized object access:** authorize every request and avoid public permanent URLs.
- **Memory exhaustion:** stream uploads/downloads and enforce limits.
- **Provider lock-in:** keep provider SDKs behind a narrow storage interface.
- **Malicious uploads:** validate type and size, use safe download headers, and add malware scanning before public release.

## Validation

The attachment proof of concept must demonstrate:

1. Add an image while online and open it from a second device.
2. Add a file offline, restart the client, reconnect, and complete the upload.
3. Simulate a lost acknowledgement and retry without creating duplicate metadata or objects.
4. Verify that a size or hash mismatch prevents the attachment from becoming available.
5. Evict a verified local file and download it again.
6. Confirm that an unverified local upload cannot be evicted.
7. Delete an attachment while another device is offline and synchronize the tombstone later.
8. Restore PostgreSQL metadata and binary storage into a clean environment.
9. Deny downloads from another authenticated account.
10. Upload a file near the configured size limit without buffering it entirely in API memory.

## Reconsider when

Revisit this decision if:

- End-to-end encryption requires the server to treat all attachment metadata differently.
- Media processing becomes a separately scaled workload.
- Very large files require a dedicated upload service.
- Regulatory requirements demand specialized scanning, retention, or regional storage.

## References

- S3-compatible object storage concepts
- HTTP range and content-disposition behaviour
- OWASP file upload security guidance
- ADR-0004 client database and local retention
- ADR-0005 local-first synchronization
- ADR-0008 personal deployment model
