import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class LocalNotes extends Table {
  TextColumn get id => text()();

  TextColumn get title => text().withLength(max: 300)();

  TextColumn get content => text()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class OutboxOperations extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get noteId => text()();

  TextColumn get operation => text()();

  DateTimeColumn get createdAt => dateTime()();

  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  TextColumn get lastError => text().nullable()();

  DateTimeColumn get nextRetryAt => dateTime().nullable()();
}

@DriftDatabase(tables: [LocalNotes, OutboxOperations])
class AppDatabase extends _$AppDatabase {
  AppDatabase({String name = 'fasty'})
    : super(
        driftDatabase(
          name: name,
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.dart.js'),
          ),
        ),
      );

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await migrator.createTable(outboxOperations);
        } else if (from < 3) {
          await migrator.addColumn(
            outboxOperations,
            outboxOperations.nextRetryAt,
          );
        }
      },
    );
  }

  Future<bool> hasPendingOperationsForNote(String noteId) async {
    final countExpression = outboxOperations.id.count();

    final query = selectOnly(outboxOperations)
      ..addColumns([countExpression])
      ..where(outboxOperations.noteId.equals(noteId));

    final row = await query.getSingle();
    final count = row.read(countExpression) ?? 0;

    return count > 0;
  }

  Future<List<OutboxOperation>> getOperationsForNote(String noteId) {
    return (select(outboxOperations)
          ..where((operation) => operation.noteId.equals(noteId))
          ..orderBy([(operation) => OrderingTerm.asc(operation.createdAt)]))
        .get();
  }

  Future<void> deleteOperationsForNote(String noteId) {
    return (delete(
      outboxOperations,
    )..where((operation) => operation.noteId.equals(noteId))).go();
  }

  Future<void> deleteOperationsForNoteByType({
    required String noteId,
    required String operationType,
  }) {
    return (delete(outboxOperations)..where(
          (operation) =>
              operation.noteId.equals(noteId) &
              operation.operation.equals(operationType),
        ))
        .go();
  }

  Stream<List<LocalNote>> watchActiveNotes() {
    return (select(localNotes)
          ..where((note) => note.isDeleted.equals(false))
          ..orderBy([(note) => OrderingTerm.desc(note.updatedAt)]))
        .watch();
  }

  Future<List<LocalNote>> getActiveNotes() {
    return (select(localNotes)
          ..where((note) => note.isDeleted.equals(false))
          ..orderBy([(note) => OrderingTerm.desc(note.updatedAt)]))
        .get();
  }

  Stream<List<LocalNote>> watchDeletedNotes() {
    return (select(localNotes)
          ..where((note) => note.isDeleted.equals(true))
          ..orderBy([(note) => OrderingTerm.desc(note.updatedAt)]))
        .watch();
  }

  Future<void> saveLocalNote(LocalNotesCompanion note) {
    return into(localNotes).insertOnConflictUpdate(note);
  }

  Future<void> markNoteDeleted({
    required String id,
    required DateTime updatedAt,
    String syncStatus = 'pending',
  }) {
    return (update(localNotes)..where((note) => note.id.equals(id))).write(
      LocalNotesCompanion(
        isDeleted: const Value(true),
        syncStatus: Value(syncStatus),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> restoreDeletedNote({
    required String id,
    required DateTime updatedAt,
  }) {
    return (update(localNotes)..where((note) => note.id.equals(id))).write(
      LocalNotesCompanion(
        isDeleted: const Value(false),
        syncStatus: const Value('pending'),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<int> purgeDeletedNotesBefore(DateTime cutoff) {
    return (delete(localNotes)..where(
          (note) =>
              note.isDeleted.equals(true) &
              (note.syncStatus.equals('synced') |
                  note.syncStatus.equals('localOnly')) &
              note.updatedAt.isSmallerThanValue(cutoff),
        ))
        .go();
  }

  Future<void> addOutboxOperation({
    required String noteId,
    required String operation,
    required DateTime createdAt,
  }) {
    return into(outboxOperations).insert(
      OutboxOperationsCompanion.insert(
        noteId: noteId,
        operation: operation,
        createdAt: createdAt,
      ),
    );
  }

  Future<List<OutboxOperation>> getPendingOperations({DateTime? now}) {
    final currentTime = (now ?? DateTime.now()).toUtc();

    return (select(outboxOperations)
          ..where(
            (operation) =>
                operation.nextRetryAt.isNull() |
                operation.nextRetryAt.isSmallerOrEqualValue(currentTime),
          )
          ..orderBy([(operation) => OrderingTerm.asc(operation.createdAt)]))
        .get();
  }

  Future<LocalNote?> getNoteById(String id) {
    return (select(
      localNotes,
    )..where((note) => note.id.equals(id))).getSingleOrNull();
  }

  Future<void> deleteOutboxOperation(int id) {
    return (delete(
      outboxOperations,
    )..where((operation) => operation.id.equals(id))).go();
  }

  Future<void> markNoteSyncedIfNoPendingOperations(String id) async {
    final hasPendingOperations = await hasPendingOperationsForNote(id);

    if (hasPendingOperations) {
      return;
    }

    await (update(localNotes)..where((note) => note.id.equals(id))).write(
      const LocalNotesCompanion(syncStatus: Value('synced')),
    );
  }

  Future<void> markOperationFailed({
    required int operationId,
    required int retryCount,
    required String error,
    DateTime? now,
  }) {
    final currentTime = (now ?? DateTime.now()).toUtc();

    // Retry after 1, 2, 4, 8, 16, 32, then at most 60 minutes.
    final exponent = retryCount <= 1 ? 0 : retryCount - 1;
    final delayMinutes = exponent >= 6 ? 60 : 1 << exponent;
    final nextRetryAt = currentTime.add(Duration(minutes: delayMinutes));

    return (update(
      outboxOperations,
    )..where((operation) => operation.id.equals(operationId))).write(
      OutboxOperationsCompanion(
        retryCount: Value(retryCount),
        lastError: Value(error),
        nextRetryAt: Value(nextRetryAt),
      ),
    );
  }

  Future<void> mergeServerNote({
    required String id,
    required String title,
    required String content,
    required DateTime createdAt,
    required DateTime updatedAt,
    required bool isDeleted,
  }) async {
    final existingNote = await getNoteById(id);

    if (existingNote != null) {
      // Never overwrite a local change that still needs uploading.
      if (existingNote.syncStatus == 'pending' ||
          existingNote.syncStatus == 'localOnly') {
        return;
      }

      // Ignore an older or identical server version.
      if (!updatedAt.isAfter(existingNote.updatedAt)) {
        return;
      }
    }

    if (isDeleted && existingNote == null) {
      // Do not recreate an already purged local tombstone.
      return;
    }

    await saveLocalNote(
      LocalNotesCompanion(
        id: Value(id),
        title: Value(title),
        content: Value(content),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        syncStatus: const Value('synced'),
        isDeleted: Value(isDeleted),
      ),
    );
  }

  Future<void> permanentlyDeleteNote(String id) {
    return (delete(localNotes)..where((note) => note.id.equals(id))).go();
  }
}
