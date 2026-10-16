import 'package:fasty/notes/note_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('checklist toolbar converts every selected line into a task', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NoteEditorPage()));

    final contentFieldFinder = find.byType(TextField).last;
    final contentField = tester.widget<TextField>(contentFieldFinder);
    final controller = contentField.controller!;

    const source = '''
Buy milk
Finish report
Call dentist''';

    await tester.enterText(contentFieldFinder, source);

    controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: source.length,
    );

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pump();

    expect(controller.text, '''
- [ ] Buy milk
- [ ] Finish report
- [ ] Call dentist''');
  });

  testWidgets(
    'checklist toolbar expands a partial selection to whole selected lines',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: NoteEditorPage()));

      final contentFieldFinder = find.byType(TextField).last;
      final contentField = tester.widget<TextField>(contentFieldFinder);
      final controller = contentField.controller!;

      const source = '''
Before
Buy milk
Finish report
After''';

      await tester.enterText(contentFieldFinder, source);

      controller.selection = const TextSelection(
        baseOffset: 9,
        extentOffset: 29,
      );

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();

      expect(controller.text, '''
Before
- [ ] Buy milk
- [ ] Finish report
After''');
    },
  );
}
