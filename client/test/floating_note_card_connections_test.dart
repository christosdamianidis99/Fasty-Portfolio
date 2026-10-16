import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/floating_note_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocalNote note() {
    final now = DateTime.utc(2026, 9, 9);

    return LocalNote(
      id: 'note',
      title: 'Connected note',
      content: 'Body',
      createdAt: now,
      updatedAt: now,
      syncStatus: 'synced',
      isDeleted: false,
    );
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    VoidCallback? onShowConnections,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 300,
              child: FloatingNoteCard(
                note: note(),
                width: 360,
                height: 300,
                onMove: (_) {},
                onResize: (_) {},
                onEdit: () {},
                onDelete: () {},
                onShowConnections: onShowConnections,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows Connected notes and invokes its callback when available', (
    tester,
  ) async {
    var openCount = 0;

    await pumpCard(tester, onShowConnections: () => openCount++);

    await tester.tap(find.byTooltip('Note options'));
    await tester.pumpAndSettle();

    expect(find.text('Connected notes'), findsOneWidget);

    await tester.tap(find.text('Connected notes'));
    await tester.pumpAndSettle();

    expect(openCount, 1);
  });

  testWidgets(
    'hides Connected notes when no connection callback is available',
    (tester) async {
      await pumpCard(tester);

      await tester.tap(find.byTooltip('Note options'));
      await tester.pumpAndSettle();

      expect(find.text('Connected notes'), findsNothing);
    },
  );
}
