import 'package:fasty/notes/note_editor.dart';
import 'package:fasty/notes/note_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editor preview renders Markdown and preserves source text', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NoteEditorPage()));

    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(2));

    await tester.enterText(
      textFields.last,
      '## Match notes\n\n**Important result**',
    );

    final previewButton = find.byTooltip('Preview');
    expect(previewButton, findsOneWidget);

    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(find.byType(NoteMarkdown), findsOneWidget);
    expect(find.text('Match notes'), findsOneWidget);
    expect(find.text('Important result'), findsOneWidget);
    expect(find.text('## Match notes'), findsNothing);
    expect(find.text('**Important result**'), findsNothing);

    final editButton = find.byTooltip('Edit');
    expect(editButton, findsOneWidget);

    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    expect(find.byType(NoteMarkdown), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));

    final restoredContentField = tester.widget<TextField>(
      find.byType(TextField).last,
    );

    expect(
      restoredContentField.controller!.text,
      '## Match notes\n\n**Important result**',
    );
  });
}
