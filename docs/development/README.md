# Development Guide

This directory documents how Fasty is developed, tested, reviewed, and prepared for release.

## Current documents

- [`testing.md`](testing.md) — test layers, synchronization matrix, platform smoke builds, real-device validation, failure evidence, and release gate

## Working principles

- Keep `main` releasable.
- Use branches and pull requests.
- Prefer small, reviewable changes.
- Add or update tests with every behavioral change.
- Add a regression test for every synchronization defect.
- Update architecture and operations documentation with the source change.
- Never commit secrets, credentials, signing keys, local SDK paths, or production data.
- Do not call a platform supported only because shared Dart code compiles.
- Do not call synchronization conflict-free when it uses last-write-wins.

## Standard client validation

From `client/`:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
```

CI additionally compiles supported platform targets as smoke tests.

## Standard backend validation

Backend changes require restore, build, and tests. Database behavior must be exercised against PostgreSQL when endpoint semantics or migrations change.

## Commit convention

Use Conventional Commit-style messages where practical:

```text
feat: add offline note creation
fix: prevent duplicate sync operations
test: cover workspace deletion across devices
docs: document conflict handling
chore: update development tooling
```

## Definition of done

A change is complete when:

- acceptance criteria are satisfied;
- relevant deterministic tests pass;
- platform smoke builds pass when target-specific code changed;
- static analysis and formatting checks pass;
- documentation is updated;
- security and privacy effects have been considered;
- database changes include migration, backup, and rollback considerations;
- the pull request explains behavior, limitations, and validation performed.

For a daily-use Android/Windows release, the real-device matrix in [`testing.md`](testing.md) must also pass against the deployed server.
