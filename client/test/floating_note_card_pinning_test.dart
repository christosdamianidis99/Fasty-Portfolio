import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/floating_note_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocalNote note() {
    final now = DateTime.utc(2026, 9, 10);

    return LocalNote(
      id: 'note',
      title: 'Pinned note test',
      content: 'Body',
      createdAt: now,
      updatedAt: now,
      syncStatus: 'synced',
      isDeleted: false,
    );
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required bool isPinned,
    required VoidCallback onTogglePinned,
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
                isPinned: isPinned,
                onTogglePinned: onTogglePinned,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('unpinned note offers Pin note', (tester) async {
    var toggleCount = 0;

    await pumpCard(
      tester,
      isPinned: false,
      onTogglePinned: () => toggleCount++,
    );

    await tester.tap(find.byTooltip('Note options'));
    await tester.pumpAndSettle();

    expect(find.text('Pin note'), findsOneWidget);
    expect(find.text('Unpin note'), findsNothing);

    await tester.tap(find.text('Pin note'));
    await tester.pumpAndSettle();

    expect(toggleCount, 1);
  });

  testWidgets('pinned note shows indicator and offers Unpin note', (
    tester,
  ) async {
    await pumpCard(tester, isPinned: true, onTogglePinned: () {});

    expect(find.byTooltip('Pinned note'), findsOneWidget);

    await tester.tap(find.byTooltip('Note options'));
    await tester.pumpAndSettle();

    expect(find.text('Unpin note'), findsOneWidget);
    expect(find.text('Pin note'), findsNothing);
  });
}
