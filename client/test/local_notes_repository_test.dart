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
    'create then multiple updates keeps only one create operation',
    () async {
      const id = 'new-note';
      final createdAt = DateTime.utc(2026, 7, 23, 10);
      final firstUpdate = createdAt.add(const Duration(minutes: 1));
      final secondUpdate = createdAt.add(const Duration(minutes: 2));

      await repository.createNote(
        id: id,
        title: 'Initial',
        content: 'Initial content',
        now: createdAt,
      );

      await repository.updateNote(
        id: id,
        title: 'Updated once',
        content: 'First update',
        createdAt: createdAt,
        updatedAt: firstUpdate,
      );

      await repository.updateNote(
        id: id,
        title: 'Updated twice',
        content: 'Second update',
        createdAt: createdAt,
        updatedAt: secondUpdate,
      );

      final operations = await database.getOperationsForNote(id);
      final note = await database.getNoteById(id);

      expect(operations, hasLength(1));
      expect(operations.single.operation, 'create');
      expect(note, isNotNull);
      expect(note!.title, 'Updated twice');
      expect(note.content, 'Second update');
      expect(note.syncStatus, 'pending');
      expect(note.isDeleted, isFalse);
    },
  );

  test(
    'new local note moves to recoverable Trash without remote delete',
    () async {
      const id = 'local-only-note';
      final createdAt = DateTime.utc(2026, 7, 23, 10);
      final deletedAt = createdAt.add(const Duration(minutes: 1));

      await repository.createNote(
        id: id,
        title: 'Temporary note',
        content: 'Recover me',
        now: createdAt,
      );

      await repository.deleteNote(id: id, updatedAt: deletedAt);

      final deletedNote = await database.getNoteById(id);
      final operations = await database.getOperationsForNote(id);

      expect(deletedNote, isNotNull);
      expect(deletedNote!.isDeleted, isTrue);
      expect(deletedNote.syncStatus, 'localOnly');
      expect(operations, isEmpty);
    },
  );

  test('restoring a local-only note recreates its create operation', () async {
    const id = 'restored-local-note';
    final createdAt = DateTime.utc(2026, 7, 23, 10);
    final deletedAt = createdAt.add(const Duration(minutes: 1));
    final restoredAt = createdAt.add(const Duration(minutes: 2));

    await repository.createNote(
      id: id,
      title: 'Temporary note',
      content: 'Recover me',
      now: createdAt,
    );
    await repository.deleteNote(id: id, updatedAt: deletedAt);

    final deletedNote = await database.getNoteById(id);
    expect(deletedNote, isNotNull);

    await repository.restoreNote(note: deletedNote!, updatedAt: restoredAt);

    final restoredNote = await database.getNoteById(id);
    final operations = await database.getOperationsForNote(id);

    expect(restoredNote, isNotNull);
    expect(restoredNote!.isDeleted, isFalse);
    expect(restoredNote.syncStatus, 'pending');
    expect(
      restoredNote.updatedAt.millisecondsSinceEpoch,
      restoredAt.millisecondsSinceEpoch,
    );
    expect(operations, hasLength(1));
    expect(operations.single.operation, 'create');
  });

  test(
    'synced note delete keeps one delete operation and local tombstone',
    () async {
      const id = 'synced-delete';
      final createdAt = DateTime.utc(2026, 7, 23, 10);
      final deletedAt = createdAt.add(const Duration(minutes: 2));

      await _saveSyncedNote(
        database,
        id: id,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      await repository.deleteNote(id: id, updatedAt: deletedAt);

      final operations = await database.getOperationsForNote(id);
      final note = await database.getNoteById(id);

      expect(operations, hasLength(1));
      expect(operations.single.operation, 'delete');
      expect(note, isNotNull);
      expect(note!.isDeleted, isTrue);
      expect(note.syncStatus, 'pending');
      expect(
        note.updatedAt.millisecondsSinceEpoch,
        deletedAt.millisecondsSinceEpoch,
      );
    },
  );

  test('restoring a server-backed note replaces delete with update', () async {
    const id = 'restore-synced-delete';
    final createdAt = DateTime.utc(2026, 7, 23, 10);
    final deletedAt = createdAt.add(const Duration(minutes: 2));
    final restoredAt = createdAt.add(const Duration(minutes: 3));

    await _saveSyncedNote(
      database,
      id: id,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await repository.deleteNote(id: id, updatedAt: deletedAt);

    final deletedNote = await database.getNoteById(id);
    await repository.restoreNote(note: deletedNote!, updatedAt: restoredAt);

    final operations = await database.getOperationsForNote(id);
    final note = await database.getNoteById(id);

    expect(note, isNotNull);
    expect(note!.isDeleted, isFalse);
    expect(note.syncStatus, 'pending');
    expect(operations, hasLength(1));
    expect(operations.single.operation, 'update');
  });

  test('permanent local removal retains delete before purge', () async {
    const id = 'permanent-delete';
    final createdAt = DateTime.utc(2026, 7, 23, 10);
    final deletedAt = createdAt.add(const Duration(minutes: 2));

    await _saveSyncedNote(
      database,
      id: id,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await repository.deleteNote(id: id, updatedAt: deletedAt);
    await repository.permanentlyDeleteNote(id);

    final note = await database.getNoteById(id);
    final operations = await database.getOperationsForNote(id);

    expect(note, isNull);
    expect(operations.map((operation) => operation.operation), [
      'delete',
      'purge',
    ]);
  });

  test('purge removes synced Trash items after fourteen days', () async {
    const oldId = 'expired-trash';
    const recentId = 'recent-trash';
    final now = DateTime.utc(2026, 7, 24, 12);
    final oldDeletedAt = now.subtract(const Duration(days: 15));
    final recentDeletedAt = now.subtract(const Duration(days: 5));

    await database.saveLocalNote(
      LocalNotesCompanion.insert(
        id: oldId,
        title: 'Expired',
        content: '',
        createdAt: oldDeletedAt.subtract(const Duration(days: 1)),
        updatedAt: oldDeletedAt,
        syncStatus: const drift.Value('synced'),
        isDeleted: const drift.Value(true),
      ),
    );

    await database.saveLocalNote(
      LocalNotesCompanion.insert(
        id: recentId,
        title: 'Recent',
        content: '',
        createdAt: recentDeletedAt.subtract(const Duration(days: 1)),
        updatedAt: recentDeletedAt,
        syncStatus: const drift.Value('synced'),
        isDeleted: const drift.Value(true),
      ),
    );

    final purged = await repository.purgeExpiredTrash(now: now);

    expect(purged, 1);
    expect(await database.getNoteById(oldId), isNull);
    expect(await database.getNoteById(recentId), isNotNull);
  });

  test('newer server tombstone moves synced note into Trash', () async {
    const id = 'server-tombstone';
    final createdAt = DateTime.utc(2026, 7, 23, 10);
    final localUpdatedAt = createdAt.add(const Duration(minutes: 5));
    final deletedAt = createdAt.add(const Duration(minutes: 10));

    await _saveSyncedNote(
      database,
      id: id,
      createdAt: createdAt,
      updatedAt: localUpdatedAt,
    );

    await database.mergeServerNote(
      id: id,
      title: 'Synced note',
      content: 'Content',
      createdAt: createdAt,
      updatedAt: deletedAt,
      isDeleted: true,
    );

    final note = await database.getNoteById(id);

    expect(note, isNotNull);
    expect(note!.isDeleted, isTrue);
    expect(note.syncStatus, 'synced');
    expect(
      note.updatedAt.millisecondsSinceEpoch,
      deletedAt.millisecondsSinceEpoch,
    );
  });

  test('server changes do not overwrite a pending local change', () async {
    const id = 'pending-local';
    final createdAt = DateTime.utc(2026, 7, 23, 10);
    final localUpdatedAt = createdAt.add(const Duration(minutes: 5));
    final serverUpdatedAt = createdAt.add(const Duration(minutes: 10));

    await database.saveLocalNote(
      LocalNotesCompanion.insert(
        id: id,
        title: 'Pending local title',
        content: 'Pending local content',
        createdAt: createdAt,
        updatedAt: localUpdatedAt,
        syncStatus: const drift.Value('pending'),
        isDeleted: const drift.Value(false),
      ),
    );

    await database.mergeServerNote(
      id: id,
      title: 'Server title',
      content: 'Server content',
      createdAt: createdAt,
      updatedAt: serverUpdatedAt,
      isDeleted: false,
    );

    final note = await database.getNoteById(id);

    expect(note, isNotNull);
    expect(note!.title, 'Pending local title');
    expect(note.content, 'Pending local content');
    expect(note.syncStatus, 'pending');
  });

  test('remaining Trash days are rounded up for the user', () async {
    final now = DateTime.utc(2026, 7, 24, 12);
    final note = LocalNote(
      id: 'countdown',
      title: 'Countdown',
      content: '',
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now.subtract(const Duration(days: 13, hours: 1)),
      syncStatus: 'synced',
      isDeleted: true,
    );

    expect(repository.trashDaysRemaining(note, now: now), 1);
  });
}

Future<void> _saveSyncedNote(
  AppDatabase database, {
  required String id,
  required DateTime createdAt,
  required DateTime updatedAt,
}) {
  return database.saveLocalNote(
    LocalNotesCompanion.insert(
      id: id,
      title: 'Synced note',
      content: 'Content',
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: const drift.Value('synced'),
      isDeleted: const drift.Value(false),
    ),
  );
}
