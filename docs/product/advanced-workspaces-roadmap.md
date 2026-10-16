# Advanced workspaces and media roadmap

## Product goal

Evolve Fasty from a text-note canvas into a local-first visual knowledge workspace while keeping Android, web, and Windows responsive, reliable, and fast.

## Delivery principles

- Stabilize canvas and synchronization before expanding the data model.
- Keep note content separate from workspace placement so one note can appear in multiple workspaces without copying its data.
- Treat binary media as attachments with explicit upload, retry, cache, and deletion states.
- Keep every local mutation transactional with its outbox operation.
- Add migrations and tests for every synchronized entity.
- Preserve exportability and avoid storing opaque editor-only data without a documented format.

## Phase 1 — stability and diagnostics

- Full-viewport infinite canvas background with zoom-correct drag and resize.
- Platform-aware local API endpoint selection.
- CORS support for Flutter web in development and production-mode containers.
- Surface partial sync failures instead of reporting false success.
- Add request timeouts and actionable connection errors.
- Cross-platform regression tests and performance profiling.

## Phase 2 — workspace model

Add synchronized entities:

- `Workspace`
  - id, name, description, color, icon, created/updated/deleted timestamps
- `WorkspaceNote`
  - workspace id, note id, x, y, width, height, z-index, appearance overrides
- `NoteLink`
  - source note id, target note id, workspace id, color, label, direction, style

A note may belong to several workspaces through `WorkspaceNote`. “Add to workspace” reuses the same note. “Duplicate note” creates a separate note with a new identifier.

## Phase 3 — attachments and media

Add `Attachment` metadata and local cache records for:

- images
- video
- voice recordings
- arbitrary files
- generated thumbnails and waveforms

Required behaviors:

- local import or recording works offline
- upload is resumable and retry-safe
- file name, MIME type, size, checksum, duration, and dimensions are retained
- open, share, rename, download, remove, and reconnect actions are available
- large media never blocks note editing or the UI thread
- cache eviction never deletes the durable server copy

## Phase 4 — file collections

Provide a `File collection` note type that contains a named directory-like hierarchy of file entries. This is a logical hierarchy managed by Fasty, not unrestricted access to the operating-system file tree.

Each entry supports:

- folders and files
- rename and move
- preview or open
- share/export
- attachment to one or more notes
- offline availability status

## Phase 5 — visual links

Render note relationships behind cards using a dedicated painter layer.

- colored curved or orthogonal connectors
- optional arrows and labels
- create by dragging from a note connection handle
- select, recolor, rename, reverse, or delete a connection
- links remain aligned while notes move or resize
- connection rendering is isolated in a repaint boundary

## Phase 6 — performance and release hardening

- persist canvas placement only at interaction end, not on every pointer frame
- rebuild only the moved note and affected connector paths
- paginate and virtualize large lists
- lazy-load media previews
- cap thumbnail resolution and decode size
- benchmark cold start, database migration, search, canvas frame time, and sync throughput
- add Android, web, Windows, backend, migration, and API integration CI
- run dependency, vulnerability, and data-loss reviews

## Later feature candidates

Features will be evaluated only after the above is stable:

- backlinks and graph exploration
- OCR and searchable attachment text
- audio transcription
- version history and note snapshots
- templates
- reminders and calendar links
- collaborative workspaces and permissions
- end-to-end encrypted private workspaces
- semantic search and local-first AI assistance
