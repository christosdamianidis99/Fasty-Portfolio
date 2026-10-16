import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

typedef NoteMarkdownTaskChanged = void Function(String updatedMarkdown);

class NoteMarkdown extends StatelessWidget {
  const NoteMarkdown({
    super.key,
    required this.data,
    this.selectable = false,
    this.onTaskChanged,
  });

  final String data;
  final bool selectable;
  final NoteMarkdownTaskChanged? onTaskChanged;

  @override
  Widget build(BuildContext context) {
    var taskIndex = 0;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final baseStyleSheet = MarkdownStyleSheet.fromTheme(theme);
    final renderedData = styleCompletedMarkdownTasks(data);

    return MarkdownBody(
      data: renderedData,
      selectable: selectable,
      styleSheet: baseStyleSheet.copyWith(
        del: baseStyleSheet.del?.copyWith(
          color: colors.onSurfaceVariant.withValues(alpha: 0.72),
        ),
      ),
      checkboxBuilder: (checked) {
        final index = taskIndex++;
        final checkbox = Container(
          key: ValueKey('markdown-task-$index'),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: checked ? colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: checked ? colors.primary : colors.outline,
              width: 1.6,
            ),
          ),
          child: checked
              ? Icon(Icons.check, size: 14, color: colors.onPrimary)
              : null,
        );

        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: onTaskChanged == null
              ? checkbox
              : InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    final updated = toggleMarkdownTask(data, taskIndex: index);
                    if (updated != data) {
                      onTaskChanged!(updated);
                    }
                  },
                  child: checkbox,
                ),
        );
      },
    );
  }
}

String styleCompletedMarkdownTasks(String markdown) {
  final taskPattern = RegExp(r'^(\s*(?:[-+*]|\d+[.)])\s+\[[xX]\]\s+)(.*)$');
  final fencePattern = RegExp(r'^\s*(`{3,}|~{3,})');

  String? activeFence;
  final sourceLines = markdown.split('\n');

  for (var i = 0; i < sourceLines.length; i++) {
    final line = sourceLines[i];
    final fenceMatch = fencePattern.firstMatch(line);

    if (fenceMatch != null) {
      final marker = fenceMatch.group(1)!;

      if (activeFence == null) {
        activeFence = marker;
      } else if (marker[0] == activeFence[0] &&
          marker.length >= activeFence.length) {
        activeFence = null;
      }

      continue;
    }

    if (activeFence != null) {
      continue;
    }

    final match = taskPattern.firstMatch(line);
    if (match == null) {
      continue;
    }

    final prefix = match.group(1)!;
    final taskText = match.group(2)!;

    sourceLines[i] = '$prefix~~$taskText~~';
  }

  return sourceLines.join('\n');
}

String toggleMarkdownTask(String markdown, {required int taskIndex}) {
  if (taskIndex < 0) {
    return markdown;
  }

  final taskPattern = RegExp(r'^(\s*(?:[-+*]|\d+[.)])\s+)\[([ xX])\]');

  final fencePattern = RegExp(r'^\s*(`{3,}|~{3,})');
  String? activeFence;
  var currentIndex = 0;
  var changed = false;

  final sourceLines = markdown.split('\n');

  for (var i = 0; i < sourceLines.length; i++) {
    final line = sourceLines[i];
    final fenceMatch = fencePattern.firstMatch(line);

    if (fenceMatch != null) {
      final marker = fenceMatch.group(1)!;

      if (activeFence == null) {
        activeFence = marker;
      } else if (marker[0] == activeFence[0] &&
          marker.length >= activeFence.length) {
        activeFence = null;
      }

      continue;
    }

    if (activeFence != null) {
      continue;
    }

    final match = taskPattern.firstMatch(line);
    if (match == null) {
      continue;
    }

    if (currentIndex++ != taskIndex) {
      continue;
    }

    final prefix = match.group(1)!;
    final marker = match.group(2)!;
    final checked = marker.trim().isNotEmpty;
    final replacement = checked ? '$prefix[ ]' : '$prefix[x]';

    sourceLines[i] = line.replaceRange(match.start, match.end, replacement);

    changed = true;
    break;
  }

  return changed ? sourceLines.join('\n') : markdown;
}
