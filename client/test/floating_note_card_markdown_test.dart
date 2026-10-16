import 'package:fasty/database/app_database.dart';
import 'package:fasty/notes/floating_note_card.dart';
import 'package:fasty/notes/note_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'floating note card renders Markdown instead of stripped source',
    (tester) async {
      final now = DateTime.utc(2026, 8, 19, 12);

      final note = LocalNote(
        id: 'desktop-markdown-note',
        title: 'Desktop formatting',
        content: '## Heading\n\n**Important text**',
        createdAt: now,
        updatedAt: now,
        syncStatus: 'synced',
        isDeleted: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 300,
                child: FloatingNoteCard(
                  note: note,
                  width: 360,
                  height: 300,
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

      expect(find.byType(NoteMarkdown), findsOneWidget);
      expect(find.text('Heading'), findsOneWidget);
      expect(find.text('Important text'), findsOneWidget);

      expect(find.text('## Heading'), findsNothing);
      expect(find.text('**Important text**'), findsNothing);

      expect(tester.takeException(), isNull);
    },
  );
}
