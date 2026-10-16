// This entry point is exclusively for creating authentic screenshots with
// disposable in-memory demo data. Normal Fasty builds use lib/main.dart.
// It never signs in, reads saved accounts, or talks to a real server.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'database/app_database.dart';
import 'main.dart';
import 'notes/local_notes_repository.dart';
import 'notes/note_editor.dart';
import 'notes/notes_api.dart';
import 'notes/notes_sync_service.dart';
import 'notes/workspace_state.dart';
import 'notes/workspace_state_store.dart';
import 'settings/app_settings_controller.dart';

const _captureView = String.fromEnvironment(
  'FASTY_CAPTURE_VIEW',
  defaultValue: 'workspace',
);

class _NoNetworkDemoSync extends NotesSyncService {
  _NoNetworkDemoSync({
    required super.database,
    required super.api,
    required super.workspaceStateStore,
  });

  @override
  Future<SyncSummary> syncPendingOperations({bool forceRetry = true}) async {
    // Intentionally avoid even a localhost HTTP request.
    return const SyncSummary();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // In-memory SQLite: no access to an installed app's notes or credentials.
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  final repository = LocalNotesRepository(database);
  final workspaceStore = WorkspaceStateStore(database);
  final workspaceId = await workspaceStore.createWorkspace(
    name: 'Productivity studio',
  );
  await workspaceStore.selectWorkspace(workspaceId);

  final samples = <({String id, String title, String content})>[
    (
      id: 'portfolio-demo-01',
      title: 'Product launch plan',
      content: '# Launch checklist\n'
          '- [x] Define MVP\n'
          '- [x] Polish onboarding\n'
          '- [ ] Test the beta release\n\n'
          '**Goal:** Make every note available offline.',
    ),
    (
      id: 'portfolio-demo-02',
      title: 'Sprint tasks',
      content: '## This week\n'
          '- [x] Review sync retries\n'
          '- [ ] Refine mobile cards\n'
          '- [ ] Prepare release notes\n\n'
          'Prioritize reliability.',
    ),
    (
      id: 'portfolio-demo-03',
      title: 'Research notes',
      content: '### Offline-first design\n'
          'Write locally first, then synchronize when a connection returns.\n\n'
          '- Durable local cache\n'
          '- Background retry queue\n'
          '- Clear sync status',
    ),
    (
      id: 'portfolio-demo-04',
      title: 'Ideas and inspiration',
      content: 'Keep the interface calm and focused.\n\n'
          '**Design themes**\n'
          '- Readable typography\n'
          '- Flexible workspaces\n'
          '- Useful connections',
    ),
  ];

  final now = DateTime.now().toUtc();
  final placements = <({double x, double y})>[
    (x: 105, y: 120),
    (x: 465, y: 155),
    (x: 155, y: 440),
    (x: 540, y: 470),
  ];

  for (var i = 0; i < samples.length; i++) {
    final item = samples[i];
    await repository.createNote(
      id: item.id,
      title: item.title,
      content: item.content,
      now: now.subtract(Duration(minutes: 12 + i * 41)),
    );
    await workspaceStore.addNoteToWorkspace(
      workspaceId: workspaceId,
      noteId: item.id,
    );
    await workspaceStore.updatePlacement(
      WorkspacePlacement(
        workspaceId: workspaceId,
        noteId: item.id,
        x: placements[i].x,
        y: placements[i].y,
        width: 310,
        height: 235,
        zIndex: i,
        pinned: i == 0,
      ),
    );
  }

  await workspaceStore.createLink(
    workspaceId: workspaceId,
    sourceNoteId: samples[0].id,
    targetNoteId: samples[1].id,
    colorValue: 0xFF006C4C,
    label: 'Next step',
  );

  final syncService = _NoNetworkDemoSync(
    database: database,
    api: NotesApi(baseUrl: 'http://127.0.0.1:9'),
    workspaceStateStore: workspaceStore,
  );

  if (_captureView == 'editor') {
    final note = await database.getNoteById(samples[0].id);
    if (note == null) {
      throw StateError('Demo note was not seeded');
    }
    runApp(
      MaterialApp(
        title: 'Fasty',
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('el')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF625BEB),
          useMaterial3: true,
        ),
        home: NoteEditorPage(note: note),
      ),
    );
    return;
  }

  runApp(
    FastyApp(
      repository: repository,
      syncService: syncService,
      workspaceStore: workspaceStore,
      settings: AppSettingsController.ephemeral(
        themeMode: ThemeMode.light,
        languageCode: 'en',
      ),
    ),
  );
}
