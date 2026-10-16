# Synchronization Architecture

This document describes the synchronization behavior implemented in the current personal alpha. Claims here apply to the code and automated tests on the active branch.

## Scope

Android and Windows use the same Flutter repositories, SQLite/Drift database, API client, workspace store, and synchronization service. Platform-specific UI code does not implement synchronization rules.

The web target shares the Dart synchronization code and compiles in CI, but browser persistence and production browser deployment still require real runtime validation.

## Local-first note writes

A note mutation is saved locally before any network request:

1. The note row is created or updated in SQLite.
2. An outbox operation is written in the same database transaction.
3. The UI immediately reads the local result.
4. Synchronization later uploads the queued operation.

Create followed by repeated edits is compacted into one create/upsert carrying the latest content. Repeated updates are compacted into one update. Deleting a note that never reached the server creates a recoverable local-only tombstone instead of sending an unnecessary remote delete.

## Synchronization cycle

Only one synchronization cycle may execute in a client process at a time.

A cycle performs these stages:

1. Read eligible outbox operations in creation order.
2. Upload each note create, update, or delete independently.
3. Record failures without preventing later independent operations from being attempted.
4. Download the authoritative note collection and merge newer server versions.
5. Reconcile the shared workspace graph using the last accepted server graph as a merge base.
6. Publish a structured status: synchronizing, synchronized, unavailable, or failed.

A user-triggered sync ignores the persisted retry delay and retries failed operations immediately. Automatic sync respects the retry schedule.

## Note conflict rule

Notes currently use last-write-wins based on the UTC `updatedAt` supplied by the client.

- A server update is accepted only when its timestamp is newer than the stored version.
- A delete is a tombstone with its own timestamp.
- A stale update cannot resurrect a newer delete.
- A newer update can intentionally restore a deleted note.
- When an upload loses to a newer server version, the server winner is merged back into the uploading device during the same cycle.
- A normal download never overwrites a local note that still has a pending operation.

### Clock requirement

Because note ordering still uses client timestamps, device clocks must be reasonably synchronized. Android and Windows should keep automatic network time enabled. A future protocol should replace client-clock ordering with server revisions.

## Workspace graph

The shared workspace graph contains:

- workspace definitions and names;
- explicit note placements and membership;
- note positions and dimensions;
- visual links between notes;
- the shared document update timestamp.

Workspace membership is explicit. Downloading a note does not automatically place it in the active workspace. If a workspace is deleted, a note that existed only there remains in the note database but becomes unassigned. It can later be placed using **Add existing note**.

A fresh installation with no accepted workspace state adopts the server graph before creating or uploading a local default graph. This prevents a new device from erasing existing workspaces.

## Device-local workspace view

The following are local navigation/view preferences and no longer create a shared pending workspace mutation:

- currently selected workspace;
- workspace camera translation;
- workspace zoom level.

When a server graph is accepted, the client preserves these local view values for workspaces that still exist. Merely opening another workspace or moving the camera on the phone therefore cannot overwrite a Windows-created placement.

## Workspace merge behavior

The server still stores one workspace JSON document. Each client additionally stores the last server document it accepted as a local merge base.

When both the local graph and the remote graph changed, the client performs a three-way merge of **base, local, and remote** before uploading a new graph:

- independent workspace additions survive;
- independent note-placement additions survive;
- independent link additions survive;
- deletion is detected by comparing absence against the common base;
- unchanged items accept the side that changed;
- identical changes converge without duplication;
- links whose source or target placement no longer exists are removed;
- the merged document receives a timestamp newer than both input documents.

During migration, an older client database may contain a pending graph but no stored merge base. In that legacy case, independent additions are combined conservatively instead of allowing an older phone snapshot to erase a new Windows placement.

### Remaining workspace limitations

This is substantially safer than whole-document timestamp replacement, but it is not yet the final revisioned protocol:

- concurrent incompatible edits to the same workspace, placement, or link still use document timestamps as the deterministic tie-breaker;
- server-side compare-and-swap/ETags are not implemented;
- workspace operations do not yet have server revisions or individual tombstone records;
- a badly incorrect device clock can still influence a same-item conflict.

The revisioned conflict-safe protocol remains tracked separately. Until then, avoid deliberately editing the same workspace property differently on two offline devices at the same time.

## Retry and failure behavior

Failed note operations remain in the outbox with:

- retry count;
- last error;
- next retry time.

Automatic retry delays grow through 1, 2, 4, 8, 16, and 32 minutes, then cap at 60 minutes. Manual sync retries immediately.

Connection failures are reported as unavailable rather than successful synchronization. Local notes, workspace state, and pending operations remain on the device.

## Deletion and Trash

A deleted server-backed note is represented locally and remotely by a tombstone. The local Trash retention window is 14 days. A pending remote delete is retained even when the local note is permanently removed, preventing a local purge from leaving the remote note alive.

Uninstalling Android removes its local SQLite database. The application must report no pending operations before uninstalling or clearing application data.

## Automated coverage

The client suite covers:

- outbox compaction;
- local-only and server-backed deletion/restoration;
- tombstone download;
- retry metadata and immediate manual retry;
- partial batch failure;
- single-flight synchronization;
- stale note conflict resolution;
- fresh-device workspace bootstrap;
- phone-to-Windows and Windows-to-phone note propagation;
- explicit multi-workspace membership;
- deleted-workspace notes remaining unassigned;
- workspace selection and camera remaining device-local;
- a phone workspace metadata change not erasing a Windows-created note placement;
- workspace-name dialog closure without Flutter lifecycle assertions.

See [`../development/testing.md`](../development/testing.md) for commands, CI targets, and the manual real-device acceptance matrix.

## Security boundary

The personal alpha is reachable only through the private Tailscale network, but the API does not yet implement Fasty user authentication or per-user authorization. Tailscale access is a network boundary, not an account system. Multi-user accounts must not be enabled until ownership is enforced by the backend and existing data is migrated safely.
