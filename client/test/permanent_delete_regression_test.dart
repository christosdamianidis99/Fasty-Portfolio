import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/local_notes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late LocalNotesRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LocalNotesRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'permanent deletion of synchronized Trash queues a server purge',
    () async {
      final timestamp = DateTime.utc(2026, 7, 27, 10);
      await database.saveLocalNote(
        LocalNotesCompanion.insert(
          id: 'synced-trash-note',
          title: 'Already in Trash',
          content: 'Delete everywhere.',
          createdAt: timestamp.subtract(const Duration(days: 1)),
          updatedAt: timestamp,
          syncStatus: const drift.Value('synced'),
          isDeleted: const drift.Value(true),
        ),
      );

      await repository.permanentlyDeleteNote('synced-trash-note');

      expect(await database.getNoteById('synced-trash-note'), isNull);
      final operations = await database.getOperationsForNote(
        'synced-trash-note',
      );
      expect(operations, hasLength(1));
      expect(operations.single.operation, 'purge');
    },
  );

  test(
    'permanent deletion keeps two stages when Trash move is pending',
    () async {
      final timestamp = DateTime.utc(2026, 7, 27, 11);
      await database.saveLocalNote(
        LocalNotesCompanion.insert(
          id: 'pending-trash-note',
          title: 'Pending Trash note',
          content: 'Soft-delete, then purge.',
          createdAt: timestamp.subtract(const Duration(days: 1)),
          updatedAt: timestamp,
          syncStatus: const drift.Value('pending'),
          isDeleted: const drift.Value(true),
        ),
      );
      await database.addOutboxOperation(
        noteId: 'pending-trash-note',
        operation: 'delete',
        createdAt: timestamp,
      );

      await repository.permanentlyDeleteNote('pending-trash-note');

      expect(await database.getNoteById('pending-trash-note'), isNull);
      final operations = await database.getOperationsForNote(
        'pending-trash-note',
      );
      expect(operations.map((operation) => operation.operation).toList(), [
        'delete',
        'purge',
      ]);
    },
  );

  test('server purge tombstones never appear in Trash', () async {
    final timestamp = DateTime.utc(2026, 7, 27, 12);
    await database.saveLocalNote(
      LocalNotesCompanion.insert(
        id: 'purged-note',
        title: LocalNotesRepository.permanentlyDeletedTitle,
        content: '',
        createdAt: timestamp.subtract(const Duration(days: 1)),
        updatedAt: timestamp,
        syncStatus: const drift.Value('synced'),
        isDeleted: const drift.Value(true),
      ),
    );

    expect(await repository.watchDeletedNotes().first, isEmpty);
  });
}
