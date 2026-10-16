# Testing and Synchronization Validation

Fasty is local-first and stores data on more than one device, so a green build alone is not sufficient evidence of reliable synchronization. This document defines the automated layers and the real-device acceptance procedure.

## Confidence levels

Use these terms precisely:

- **Compiled** — source builds for a target platform.
- **Unit-tested** — an isolated rule passes deterministic tests.
- **Simulated cross-device tested** — two independent local databases converge through a stateful fake server.
- **Backend integration tested** — requests run against the ASP.NET Core API and PostgreSQL.
- **Real-device validated** — the signed Android app and Windows application complete the manual matrix through the deployed laptop server.

No finite test suite proves synchronization is perfect. A release is acceptable when all applicable automated layers are green, known limitations are documented, and the real-device matrix passes without data loss or silent reassignment.

## Client quality commands

From `client/`:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
```

## Client test layers

### Repository tests

`local_notes_repository_test.dart` verifies local transactions and outbox compaction:

- create plus repeated edits;
- local-only deletion and restoration;
- server-backed deletion and restoration;
- permanent removal with a retained remote delete;
- Trash retention;
- server tombstones;
- protection of pending local edits.

### Workspace-store tests

`workspace_state_store_test.dart` verifies:

- default workspace creation;
- persisted placement changes;
- one note identity shared across workspaces;
- visual link creation and deletion.

### Synchronization-service tests

`notes_sync_service_test.dart` verifies:

- one failed operation does not block later operations;
- overlapping sync requests are single-flight;
- remote workspace deletion does not automatically move notes.

### Cross-device simulation

`cross_device_sync_test.dart` creates two independent in-memory Drift databases named conceptually as phone and Windows. Both use the real repository, API client, workspace store, and synchronization service against one stateful fake server.

It verifies:

1. phone-created workspace and note converge on Windows;
2. workspace deletion leaves its note unassigned rather than moving it;
3. edits and deletes round-trip in both directions;
4. offline operations remain queued and manual sync retries them;
5. stale offline edits accept the newer server winner;
6. a fresh installation adopts the remote workspace graph without uploading its default;
7. one note keeps one identity when explicitly placed in two workspaces.

The fake server implements the same current last-write-wins timestamp rules as the API. It is deterministic and does not replace backend integration or real networking tests.

## Native Linux R3 regression

The self-driving integration harness runs compiled Linux widgets, real Linux preferences, and the live read-only release-announcement endpoint. Workspace and connection flows use disposable local databases. It does not authenticate a real account, reset passwords, or substitute for live Google consent, server backup restoration, or Android/Windows acceptance.

Run from `client/` in Bash:

```bash
r3_data_dir="$(mktemp -d /tmp/fasty-r3-native.XXXXXX)"
mkdir -p "$r3_data_dir/config" "$r3_data_dir/data"

XDG_CONFIG_HOME="$r3_data_dir/config" XDG_DATA_HOME="$r3_data_dir/data" FASTY_R3_ISOLATED=1 \
flutter drive -d linux --driver=test_driver/integration_test.dart \
  --target=integration_test/linux_r3_test.dart \
  --dart-define=FASTY_API_BASE_URL=http://127.0.0.1 \
  --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false

# Reuse the same isolated directories in a separate app process.
XDG_CONFIG_HOME="$r3_data_dir/config" XDG_DATA_HOME="$r3_data_dir/data" FASTY_R3_ISOLATED=1 \
flutter drive -d linux --driver=test_driver/integration_test.dart \
  --target=integration_test/linux_r3_test.dart \
  --dart-define=FASTY_API_BASE_URL=http://127.0.0.1 \
  --dart-define=FASTY_R3_RESTART_CHECK=true \
  --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false

# Restore the ordinary app entry point in the local build output afterward.
flutter build linux --debug \
  --dart-define=FASTY_API_BASE_URL=http://127.0.0.1
```

A live announcement must be enabled and unchanged between the two runs. The harness refuses preference access unless both XDG directories are under a temporary `fasty-r3-` directory and `FASTY_R3_ISOLATED=1`. Native result-channel reporting is disabled because the Flutter driver collects the results on Linux; Android instrumentation and XCTest are not used here.

Checks:

- create a directed connection, follow it to an off-screen target, verify centering, delete it, and preserve both notes;
- switch workspaces, delete a disposable workspace, and recover its unchanged note through Add existing note;
- fetch and display the current live release notice, dismiss it, and persist acknowledgment through the native preferences plugin;
- start a separate process and verify the same release is still acknowledged.

## Platform build smoke tests

CI should compile these targets from the same commit:

- Android debug APK;
- Windows debug application;
- web release bundle.

A platform smoke build detects conditional imports, plugin registration failures, manifest problems, and target-specific compile errors. It does not prove runtime storage or networking behavior.

## Backend tests

Backend validation should include:

- build with warnings treated consistently;
- unit tests for note timestamp and tombstone rules;
- API integration tests against PostgreSQL for health, note upsert/delete ordering, and workspace document ordering;
- migration startup on an empty database.

The CI workflow must run `dotnet test`, not only `dotnet build`, once the backend test project is present.

## Manual real-device acceptance matrix

Use a disposable, isolated test server; do not run acceptance scenarios against the personal production deployment. Keep your local test network connected unless a step explicitly tests offline behavior.

Before starting:

1. Confirm `GET /health` reports healthy.
2. Confirm `GET /health/ready` reports ready.
3. Confirm both clients run the same Git commit/build version.
4. Confirm the Sync details panel has no pending operations on either device.
5. Record a disposable test workspace name and note IDs/titles.

### A. Phone to Windows

1. On phone, create workspace `SYNC-PHONE`.
2. Create note `P1` inside it.
3. Edit `P1` twice before syncing.
4. Synchronize phone.
5. Synchronize Windows.
6. Verify one `P1` exists, with the latest content, only in `SYNC-PHONE`.

### B. Windows to phone

1. On Windows, create note `W1` in a separate workspace.
2. Move and resize it on the desktop canvas.
3. Synchronize Windows, then phone.
4. Verify phone shows `W1` in the correct workspace using the mobile card layout.
5. Verify Windows retains its desktop position after restart.

### C. Explicit shared membership

1. Add `P1` to a second workspace on Windows.
2. Synchronize Windows, then phone.
3. Verify both workspaces show the same note content.
4. Edit the note from phone and synchronize both devices.
5. Verify both placements show the updated single note.

### D. Workspace deletion regression

1. Create a disposable workspace containing a note that exists nowhere else.
2. Synchronize both devices.
3. Delete the workspace on phone and synchronize.
4. Synchronize Windows.
5. Verify the workspace is gone.
6. Verify the note does not appear in any unrelated workspace.
7. Verify the note is available through **Add existing note**.

### E. Offline retry

1. Disable network access for the disposable test client.
2. Create and edit a note.
3. Trigger sync.
4. Verify Sync unavailable appears and the pending detail includes title, action, workspace, and error.
5. Restart the app while still offline and verify the note remains.
6. Reconnect and press Sync now.
7. Verify the pending item clears and Windows receives the note.

### F. Note conflict

1. Synchronize both devices to the same note version.
2. Disconnect both.
3. Edit the same note differently on both devices.
4. Reconnect and synchronize one device, then the other.
5. Verify both converge to the version with the later UTC timestamp.
6. Record the result; do not treat last-write-wins as a merge of both texts.

### G. Trash and restore

1. Delete a synchronized note on phone.
2. Synchronize both devices and verify it appears in Trash on both.
3. Restore it from Windows.
4. Synchronize both and verify it is active again.
5. Confirm no duplicate note is created.

### H. Restart behavior

1. Close both applications completely.
2. Restart only the disposable test server or its Docker services.
3. Confirm health and readiness return.
4. Reopen phone and Windows clients.
5. Verify local notes are immediately visible before sync.
6. Synchronize and verify no unexpected workspace changes occur.

## Failure reporting

For every failed acceptance step, capture:

- client platform and build commit;
- action performed;
- Sync details status and pending rows;
- whether the device was online;
- server UTC time;
- API container logs around the event;
- expected and actual workspace membership;
- whether data still exists locally.

Never repair a failure by uninstalling the app or deleting volumes before pending data and logs are inspected.

## Release gate

A release candidate is ready for supported test-device use only when:

- Flutter formatting, analysis, and tests pass;
- backend build and tests pass;
- Android and Windows smoke builds pass;
- the real-device matrix passes for the release commit;
- the server database has a verified backup;
- known conflict limitations are accepted and documented.
