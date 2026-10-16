# R3 regression checkpoint — sanitized summary

> Historical engineering record from September 30, 2026. The original internal checkpoint with personal deployment details is retained only in the private safeguard history. This summary is appropriate for documentation review; it is **not** evidence of a production security assessment or a complete public release.

## Automated verification reported during R3

| Layer | Recorded result | Scope |
| --- | --- | --- |
| Flutter widget/unit tests | **226 passed** | Final follow-up suite, including additional UI and persistence regressions |
| Flutter static analysis | **No issues** | Final follow-up |
| Dart formatting | **102 files checked, no changes** | Final follow-up |
| .NET backend tests | **164 passed** | Earlier R3 checkpoint, after which no backend code changed |
| Android | **Debug APK built** | Earlier R3 checkpoint |
| Linux | **Debug application built and launched** | Final follow-up |
| Desktop task filters | **Manually confirmed on Linux** | Final follow-up |

These figures were recorded in the project checkpoint and should be independently confirmed by CI for the publication candidate.

## Regression scenarios added

- Workspace deletion and recovery of a note through **Add existing note**.
- Actual SQLite database close-and-reopen preserving queued edits, workspace state, pinning, and note links.
- Desktop directed-note connection creation, navigation/focus, and removal.
- Task-progress badges matching checklist state.
- Cross-device sync retry and Trash behavior.

## Explicit remaining limitations

- Android and Windows real-device acceptance were not completed at this checkpoint.
- Live two-device offline conflicts, login/session revocation, and release notice acknowledgment still required native acceptance.
- Google sign-in was mocked/tested and an invalid token rejected; **successful live Google OAuth was not demonstrated**.
- Assisted password recovery has automated coverage, but deployed account recovery needs a disposable test account.
- Server database backup-and-restore verification remains open.
- Sync uses last-write-wins timestamps. Tests do not prove a conflict-free editing model.

For reproducible commands and the acceptance matrix, see [development testing](development/testing.md) and the [CI workflow](../.github/workflows/flutter-ci.yml).
