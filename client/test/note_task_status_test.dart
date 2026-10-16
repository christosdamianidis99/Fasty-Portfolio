import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/floating_note_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'card status follows checklist edits and ignores fenced examples',
    (tester) async {
      Future<void> show(String content) async {
        final now = DateTime.utc(2026, 9, 30);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  height: 240,
                  child: FloatingNoteCard(
                    note: LocalNote(
                      id: 'status-test',
                      title: 'Checklist',
                      content: content,
                      createdAt: now,
                      updatedAt: now,
                      syncStatus: 'synced',
                      isDeleted: false,
                    ),
                    width: 280,
                    height: 240,
                    onMove: (_) {},
                    onResize: (_) {},
                    onEdit: () {},
                    onDelete: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Synced'), findsOneWidget);
      }

      await show('Ordinary text');
      expect(find.text('Plain note'), findsOneWidget);
      await show('- [ ] First\n- [ ] Second');
      expect(find.text('To do · 0/2'), findsOneWidget);
      await show('- [x] First\n- [ ] Second');
      expect(find.text('In progress · 1/2'), findsOneWidget);
      await show('- [x] First\n- [x] Second');
      expect(find.text('Completed · 2/2'), findsOneWidget);
      await show('- [ ] First\n- [x] Second');
      expect(find.text('In progress · 1/2'), findsOneWidget);
      await show('```\n- [ ] Example\n```');
      expect(find.text('Plain note'), findsOneWidget);
    },
  );
}
