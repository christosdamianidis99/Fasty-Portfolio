import 'package:flutter_test/flutter_test.dart';
import 'package:fasty/notes/task_progression.dart';
import 'package:fasty/notes/workspace_state.dart';

void main() {
  group('markdownTaskProgress', () {
    test('counts completed and remaining Markdown tasks', () {
      final progress = markdownTaskProgress(
        '- [x] Research\n'
        '- [ ] Write report\n'
        '- [X] Submit draft',
      );

      expect(progress.total, 3);
      expect(progress.completed, 2);
      expect(progress.remaining, 1);
      expect(progress.hasTasks, isTrue);
      expect(progress.isComplete, isFalse);
    });

    test('reports a task note complete only when every task is checked', () {
      final progress = markdownTaskProgress(
        '- [x] Research\n'
        '- [X] Write report',
      );

      expect(progress.total, 2);
      expect(progress.completed, 2);
      expect(progress.remaining, 0);
      expect(progress.isComplete, isTrue);
    });

    test('does not treat a note without tasks as completed', () {
      final progress = markdownTaskProgress(
        'Just an ordinary note.\n'
        '- ordinary bullet',
      );

      expect(progress.total, 0);
      expect(progress.completed, 0);
      expect(progress.remaining, 0);
      expect(progress.hasTasks, isFalse);
      expect(progress.isComplete, isFalse);
    });

    test('ignores task-like Markdown inside fenced code blocks', () {
      final progress = markdownTaskProgress(
        '- [x] Real task\n'
        '```markdown\n'
        '- [ ] Example only\n'
        '```\n'
        '- [ ] Real remaining task',
      );

      expect(progress.total, 2);
      expect(progress.completed, 1);
      expect(progress.remaining, 1);
    });
  });

  group('isTaskProgressionLink', () {
    NoteLinkDefinition link({required String label, bool directed = true}) {
      final timestamp = DateTime.utc(2026, 9, 9);

      return NoteLinkDefinition(
        id: 'link',
        workspaceId: 'workspace',
        sourceNoteId: 'source',
        targetNoteId: 'target',
        colorValue: 0xFF625BEB,
        label: label,
        directed: directed,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
    }

    test('recognizes the canonical Next task directed connection', () {
      expect(
        isTaskProgressionLink(link(label: taskProgressionLinkLabel)),
        isTrue,
      );
    });

    test('accepts harmless label whitespace and casing', () {
      expect(isTaskProgressionLink(link(label: '  NEXT TASK  ')), isTrue);
    });

    test('does not treat ordinary connections as task progression', () {
      expect(isTaskProgressionLink(link(label: 'depends on')), isFalse);
    });

    test('requires task progression connections to be directed', () {
      expect(
        isTaskProgressionLink(
          link(label: taskProgressionLinkLabel, directed: false),
        ),
        isFalse,
      );
    });

    test('progression is ready only when source tasks are complete', () {
      final progression = link(label: taskProgressionLinkLabel);

      expect(
        isTaskProgressionReady(
          progression,
          '- [x] Research\n- [ ] Write report',
        ),
        isFalse,
      );

      expect(
        isTaskProgressionReady(
          progression,
          '- [x] Research\n- [x] Write report',
        ),
        isTrue,
      );
    });

    test('progression without source tasks is not ready', () {
      expect(
        isTaskProgressionReady(
          link(label: taskProgressionLinkLabel),
          'Ordinary note',
        ),
        isFalse,
      );
    });

    test('collects ready progression links and target notes', () {
      final ready = link(label: taskProgressionLinkLabel);
      final blocked = NoteLinkDefinition(
        id: 'blocked',
        workspaceId: 'workspace',
        sourceNoteId: 'second-source',
        targetNoteId: 'second-target',
        colorValue: 0xFF625BEB,
        label: taskProgressionLinkLabel,
        directed: true,
        createdAt: DateTime.utc(2026, 9, 9),
        updatedAt: DateTime.utc(2026, 9, 9),
      );

      final contents = {
        'source': '- [x] Complete',
        'second-source': '- [ ] Remaining',
      };

      expect(
        readyTaskProgressionLinkIds(
          links: [ready, blocked],
          noteContents: contents,
        ),
        {'link'},
      );

      expect(
        readyTaskProgressionTargetIds(
          links: [ready, blocked],
          noteContents: contents,
        ),
        {'target'},
      );
    });

    test('fires only when progression becomes complete', () {
      expect(
        didTaskProgressionBecomeReady(
          beforeMarkdown: '- [x] First\n- [ ] Second',
          afterMarkdown: '- [x] First\n- [x] Second',
        ),
        isTrue,
      );
    });

    test('does not fire again when note was already complete', () {
      expect(
        didTaskProgressionBecomeReady(
          beforeMarkdown: '- [x] First\n- [x] Second',
          afterMarkdown: '- [x] First\n- [x] Second',
        ),
        isFalse,
      );
    });

    test('does not fire when a completed note becomes incomplete', () {
      expect(
        didTaskProgressionBecomeReady(
          beforeMarkdown: '- [x] First\n- [x] Second',
          afterMarkdown: '- [x] First\n- [ ] Second',
        ),
        isFalse,
      );
    });
  });
}
