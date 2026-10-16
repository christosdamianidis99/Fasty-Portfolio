import 'package:fasty/notes/note_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toggles the requested unordered Markdown task only', () {
    const markdown = '''
- [ ] First task
- [x] Second task
- [ ] Third task
''';

    final updated = toggleMarkdownTask(markdown, taskIndex: 1);

    expect(updated, '''
- [ ] First task
- [ ] Second task
- [ ] Third task
''');
  });

  test('toggles unchecked task to checked', () {
    const markdown = '- [ ] Buy milk';

    expect(toggleMarkdownTask(markdown, taskIndex: 0), '- [x] Buy milk');
  });

  test('leaves Markdown unchanged when task index does not exist', () {
    const markdown = '- [ ] Buy milk';

    expect(toggleMarkdownTask(markdown, taskIndex: 4), markdown);
  });

  testWidgets('interactive Markdown task emits updated source', (tester) async {
    String? updated;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteMarkdown(
            data: '- [ ] Buy milk\n- [x] Write report',
            onTaskChanged: (value) => updated = value,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('markdown-task-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('markdown-task-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('markdown-task-0')));
    await tester.pump();

    expect(updated, '- [x] Buy milk\n- [x] Write report');
  });

  test('ignores task-like Markdown inside fenced code blocks', () {
    const markdown =
        '```'
        '\n- [ ] Example inside code'
        '\n```'
        '\n- [ ] Real task';

    final updated = toggleMarkdownTask(markdown, taskIndex: 0);

    expect(
      updated,
      '```'
      '\n- [ ] Example inside code'
      '\n```'
      '\n- [x] Real task',
    );
  });
  test('styles checked tasks without changing unchecked tasks', () {
    const markdown = '- [x] Finished task\n- [ ] Pending task';

    expect(
      styleCompletedMarkdownTasks(markdown),
      '- [x] ~~Finished task~~\n- [ ] Pending task',
    );
  });

  test('completed task styling preserves inner Markdown formatting', () {
    const markdown = '- [x] Buy **milk** and _bread_';

    expect(
      styleCompletedMarkdownTasks(markdown),
      '- [x] ~~Buy **milk** and _bread_~~',
    );
  });

  test('completed task styling ignores fenced code blocks', () {
    const markdown =
        '```'
        '\n- [x] Example inside code'
        '\n```'
        '\n- [x] Real task';

    expect(
      styleCompletedMarkdownTasks(markdown),
      '```'
      '\n- [x] Example inside code'
      '\n```'
      '\n- [x] ~~Real task~~',
    );
  });

  testWidgets('NoteMarkdown uses styled render data without changing source', (
    tester,
  ) async {
    const source = '- [x] Finished task\n- [ ] Pending task';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NoteMarkdown(data: source)),
      ),
    );

    final markdownBody = tester.widget<MarkdownBody>(find.byType(MarkdownBody));

    expect(markdownBody.data, '- [x] ~~Finished task~~\n- [ ] Pending task');

    expect(source, '- [x] Finished task\n- [ ] Pending task');
  });
}
