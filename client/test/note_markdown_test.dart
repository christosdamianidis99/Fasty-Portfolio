import 'package:fasty/notes/note_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject({required String data, bool selectable = false}) {
    return MaterialApp(
      home: Scaffold(
        body: NoteMarkdown(data: data, selectable: selectable),
      ),
    );
  }

  testWidgets('renders Markdown through MarkdownBody', (tester) async {
    await tester.pumpWidget(buildSubject(data: '**Bold text**'));

    expect(find.byType(NoteMarkdown), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text('Bold text'), findsOneWidget);
    expect(find.text('**Bold text**'), findsNothing);
  });

  testWidgets('passes selectable mode to MarkdownBody', (tester) async {
    await tester.pumpWidget(
      buildSubject(data: 'Selectable note', selectable: true),
    );

    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));

    expect(markdown.selectable, isTrue);
  });

  testWidgets('renders common note formatting without source markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        data: '''
## Heading

- First item
- Second item

> Important quote

`inline code`
''',
      ),
    );

    expect(find.text('Heading'), findsOneWidget);
    expect(find.text('First item'), findsOneWidget);
    expect(find.text('Second item'), findsOneWidget);
    expect(find.text('Important quote'), findsOneWidget);
    expect(find.text('inline code'), findsOneWidget);
  });
}
