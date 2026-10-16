import 'package:flutter/material.dart';
import '../settings/app_strings.dart';
import 'task_progression.dart';

/// Shares checklist rules with the workspace filters.
class NoteTaskStatus extends StatelessWidget {
  const NoteTaskStatus({super.key, required this.content});
  final String content;

  @override
  Widget build(BuildContext context) {
    final progress = markdownTaskProgress(content);
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final String state;
    final IconData icon;
    if (!progress.hasTasks) {
      state = strings.pick('Plain note', 'Απλή σημείωση');
      icon = Icons.notes_rounded;
    } else if (progress.isComplete) {
      state = strings.pick('Completed', 'Ολοκληρώθηκε');
      icon = Icons.check_circle_outline_rounded;
    } else if (progress.completed == 0) {
      state = strings.pick('To do', 'Προς ολοκλήρωση');
      icon = Icons.radio_button_unchecked_rounded;
    } else {
      state = strings.pick('In progress', 'Σε εξέλιξη');
      icon = Icons.pending_actions_rounded;
    }
    final label = progress.hasTasks
        ? '$state · ${progress.completed}/${progress.total}'
        : state;
    final foreground = progress.isComplete
        ? colors.onPrimaryContainer
        : colors.onSurfaceVariant;
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: progress.isComplete
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
