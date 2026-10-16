import 'package:drift/native.dart';
import 'package:fasty/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('testing constructor remains available', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    try {
      expect(await database.getActiveNotes(), isEmpty);
    } finally {
      await database.close();
    }
  });
}
