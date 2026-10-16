import 'package:fasty/notes/note_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'note Markdown surface renders formatted text without source markers',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 160,
              child: NoteMarkdown(
                data: '## Heading\n\n**Important**\n\n- First item',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Heading'), findsOneWidget);
      expect(find.text('Important'), findsOneWidget);
      expect(find.text('First item'), findsOneWidget);

      expect(find.text('## Heading'), findsNothing);
      expect(find.text('**Important**'), findsNothing);

      expect(tester.takeException(), isNull);
    },
  );
}
