# Fasty — MVP Requirements

## Document status

- Status: Draft
- Product stage: Personal MVP
- Priority notation: Must, Should, Could

## Functional requirements

### Authentication

- **FR-AUTH-001 — Must:** A user can register an account using an email address and password.
- **FR-AUTH-002 — Must:** A registered user can sign in and receive an authenticated session.
- **FR-AUTH-003 — Must:** A user can sign out from the current device.
- **FR-AUTH-004 — Must:** The same account can be used concurrently on multiple devices.
- **FR-AUTH-005 — Should:** A user can view and revoke active device sessions.
- **FR-AUTH-006 — Should:** The system supports password reset.

### Note management

- **FR-NOTE-001 — Must:** A user can create a plain-text note.
- **FR-NOTE-002 — Must:** A user can edit a note.
- **FR-NOTE-003 — Must:** Changes are saved locally without requiring an explicit save action.
- **FR-NOTE-004 — Must:** A user can delete a note.
- **FR-NOTE-005 — Must:** A deleted note remains recoverable for a defined retention period.
- **FR-NOTE-006 — Must:** Notes display creation and last-modified timestamps.
- **FR-NOTE-007 — Should:** A user can pin and unpin a note.
- **FR-NOTE-008 — Should:** Notes can be sorted by last modification time.

### Local-first operation

- **FR-LOCAL-001 — Must:** Notes are stored in a local database on every supported client.
- **FR-LOCAL-002 — Must:** A user can read existing notes while offline.
- **FR-LOCAL-003 — Must:** A user can create, edit, and delete notes while offline.
- **FR-LOCAL-004 — Must:** Offline changes are queued for later synchronization.
- **FR-LOCAL-005 — Must:** The application remains usable when the backend is unavailable.

### Synchronization

- **FR-SYNC-001 — Must:** Local changes are pushed to the authenticated user's server account.
- **FR-SYNC-002 — Must:** Remote changes are downloaded incrementally.
- **FR-SYNC-003 — Must:** A note changed on one connected device appears on another connected device without requiring an application restart.
- **FR-SYNC-004 — Must:** Failed synchronization operations are retried.
- **FR-SYNC-005 — Must:** Retrying the same operation does not create duplicate data.
- **FR-SYNC-006 — Must:** Deletions synchronize across devices.
- **FR-SYNC-007 — Must:** Conflicting edits are detected.
- **FR-SYNC-008 — Must:** Conflict handling does not silently discard note content.
- **FR-SYNC-009 — Must:** A client can resume synchronization after being offline for an extended period.
- **FR-SYNC-010 — Should:** The application displays whether changes are local-only, synchronizing, synchronized, or failed.
- **FR-SYNC-011 — Should:** Connected clients receive a notification that new changes are available.

### Search and organization

- **FR-ORG-001 — Must:** A user can search note titles.
- **FR-ORG-002 — Must:** A user can search note content.
- **FR-ORG-003 — Could:** A user can organize notes using tags.
- **FR-ORG-004 — Could:** A user can organize notes using folders or notebooks.

### Export and recovery

- **FR-DATA-001 — Must:** A user can export their notes in at least one human-readable format.
- **FR-DATA-002 — Must:** The server database can be backed up automatically.
- **FR-DATA-003 — Must:** A documented restoration procedure exists.
- **FR-DATA-004 — Must:** Restoration is tested before the personal MVP is considered complete.
- **FR-DATA-005 — Should:** Note history is retained for a limited period.

## Non-functional requirements

### Security

- **NFR-SEC-001:** All production and remote personal traffic must use encrypted transport.
- **NFR-SEC-002:** Every server-side data access must verify the authenticated owner.
- **NFR-SEC-003:** Passwords must be stored using an established adaptive password-hashing mechanism.
- **NFR-SEC-004:** Authentication tokens must be stored using platform-appropriate secure storage.
- **NFR-SEC-005:** Secrets must not be committed to source control.
- **NFR-SEC-006:** PostgreSQL must not be exposed directly to the public internet.
- **NFR-SEC-007:** Logs must not contain passwords, tokens, or full note content by default.

### Reliability

- **NFR-REL-001:** A local edit must be durable before the UI reports it as saved.
- **NFR-REL-002:** Synchronization requests must be safe to retry.
- **NFR-REL-003:** Temporary network failure must not result in lost note content.
- **NFR-REL-004:** Server-side note changes and synchronization metadata must be committed transactionally.
- **NFR-REL-005:** Backup failures must be detectable.

### Performance

- **NFR-PERF-001:** Opening the local note list should not require a network request.
- **NFR-PERF-002:** Local text changes should be reflected in the UI immediately.
- **NFR-PERF-003:** Synchronization should transfer only relevant changes rather than the complete dataset for every request.
- **NFR-PERF-004:** Note-list rendering should remain responsive with at least 10,000 personal notes.

### Portability

- **NFR-PORT-001:** The first supported clients are Android, Windows, and web.
- **NFR-PORT-002:** Business and synchronization rules should not depend on a single operating system.
- **NFR-PORT-003:** Backend deployment configuration must be externalized from application code.
- **NFR-PORT-004:** The backend must be movable from the Lubuntu host to cloud infrastructure without changing domain logic.

### Maintainability

- **NFR-MAINT-001:** Important architectural choices must be recorded as Architecture Decision Records.
- **NFR-MAINT-002:** Database schema changes must use version-controlled migrations.
- **NFR-MAINT-003:** Core synchronization logic must have automated tests.
- **NFR-MAINT-004:** Public API contracts must be documented using OpenAPI.
- **NFR-MAINT-005:** Development and deployment setup must be reproducible from repository documentation.

### Observability

- **NFR-OBS-001:** The backend must expose a health endpoint.
- **NFR-OBS-002:** Backend logs must be structured.
- **NFR-OBS-003:** Synchronization failures must be diagnosable without logging note bodies.
- **NFR-OBS-004:** Backup execution and restoration tests must produce verifiable results.

## MVP acceptance scenarios

### Scenario 1 — Cross-device creation

1. Sign in on Windows and Android using the same account.
2. Create a note on Windows.
3. Wait for synchronization.
4. Confirm that the note appears on Android with identical content.

Expected result: The note is available on both devices and has one logical identity.

### Scenario 2 — Offline creation

1. Disconnect Android from the network.
2. Create and edit a note.
3. Close and reopen the application.
4. Confirm that the note remains available.
5. Reconnect the device.
6. Confirm that the note appears on Windows.

Expected result: No content is lost and the note synchronizes once.

### Scenario 3 — Retry safety

1. Submit a note change.
2. Interrupt the response after the server may have processed it.
3. Retry the operation.

Expected result: The server contains one logical change, not duplicates.

### Scenario 4 — Conflicting edits

1. Synchronize the same note to two devices.
2. Disconnect both devices.
3. Edit the note differently on each device.
4. Reconnect both devices.

Expected result: Fasty detects the conflict and preserves both versions or otherwise guarantees recoverability.

### Scenario 5 — Backend outage

1. Stop the personal backend.
2. Open, create, and edit notes locally.
3. Restart the backend.

Expected result: The application remains usable during the outage and later synchronizes queued changes.

### Scenario 6 — Backup restoration

1. Create representative notes.
2. Produce a database backup.
3. Restore into a clean environment.
4. Sign in and verify the data.

Expected result: Notes, ownership, deletion state, and synchronization metadata are restored correctly.
