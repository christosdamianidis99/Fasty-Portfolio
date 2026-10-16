# Fasty Flutter client

This is the Flutter front end of [Fasty](../README.md), an **offline-first notes and visual workspaces** engineering portfolio project. The API and database are in `../backend` and `../infrastructure`.

## Stack

- Flutter / Dart with Android and desktop targets
- SQLite and Drift for persisted notes, workspace state, and queued local mutations
- REST synchronization to an ASP.NET Core API
- Secure storage for account sessions
- Markdown editing, tasks/checklists, visual connections, note search and organization

## Local development

Start a disposable local backend by following the [root README](../README.md) and [local operations guide](../docs/operations/README.md).

~~~bash
flutter pub get
flutter run -d linux --dart-define=FASTY_API_BASE_URL=http://127.0.0.1:8080
~~~

Select a target supported by your installed Flutter toolchain. For a Windows development host, use `-d windows`; Android emulators may need `http://10.0.2.2:8080`. Physical Android devices require a reachable, appropriately secured server endpoint. The local HTTP example must **not** be used for public Internet deployment.

## Checks

~~~bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
~~~

A Linux-only R3 integration test harness exists in `integration_test/`. It deliberately requires isolated temporary preferences/data directories and a separately configured test API. Don't run it against real user data or production credentials.

The application supports platform-specific builds, but a passing build is not proof of native runtime validation. See the [testing and acceptance matrix](../docs/development/testing.md) and [R3 checkpoint summary](../docs/R3_CHECKPOINT_2026-09-30.md).

## Status

This is an independently developed **engineering portfolio project**, not a managed consumer product. See the root [security notice](../SECURITY.md) and third-party notices before hosting an API or redistributing packages.
