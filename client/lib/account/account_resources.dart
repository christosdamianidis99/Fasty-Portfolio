import '../database/account_database_name.dart';
import '../database/app_database.dart';
import '../notes/local_notes_repository.dart';
import '../notes/notes_api.dart';
import '../notes/notes_sync_service.dart';
import '../notes/workspace_state_store.dart';

class AccountResources {
  AccountResources({
    required this.database,
    required this.repository,
    required this.notesApi,
    required this.syncService,
    required this.workspaceStore,
  });

  factory AccountResources.create({
    required String email,
    required String apiBaseUrl,
    required AccessTokenProvider accessTokenProvider,
  }) {
    final database = AppDatabase(name: accountDatabaseName(email));
    final repository = LocalNotesRepository(database);
    final workspaceStore = WorkspaceStateStore(database);
    final notesApi = NotesApi(
      baseUrl: apiBaseUrl,
      accessTokenProvider: accessTokenProvider,
    );
    final syncService = NotesSyncService(
      database: database,
      api: notesApi,
      workspaceStateStore: workspaceStore,
    );

    return AccountResources(
      database: database,
      repository: repository,
      notesApi: notesApi,
      syncService: syncService,
      workspaceStore: workspaceStore,
    );
  }

  final AppDatabase database;
  final LocalNotesRepository repository;
  final NotesApi notesApi;
  final NotesSyncService syncService;
  final WorkspaceStateStore workspaceStore;

  Future<void> dispose() async {
    notesApi.close();
    await syncService.dispose();
    await workspaceStore.dispose();
    await database.close();
  }
}
