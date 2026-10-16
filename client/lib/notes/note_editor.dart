import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/app_database.dart';
import '../settings/app_strings.dart';
import 'note_markdown.dart';

class NoteEditorResult {
  const NoteEditorResult({required this.title, required this.content});

  final String title;
  final String content;
}

Future<NoteEditorResult?> showNoteEditor(
  BuildContext context, {
  LocalNote? note,
}) {
  return Navigator.of(context).push<NoteEditorResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => NoteEditorPage(note: note),
    ),
  );
}

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key, this.note});

  final LocalNote? note;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final FocusNode _contentFocusNode;

  bool _isDirty = false;
  bool _showPreview = false;

  bool get _isEditing => widget.note != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(
      text: widget.note?.content ?? '',
    );
    _contentFocusNode = FocusNode();
    _titleController.addListener(_markDirty);
    _contentController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_markDirty)
      ..dispose();
    _contentController
      ..removeListener(_markDirty)
      ..dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_isDirty && mounted) {
      setState(() => _isDirty = true);
    }
  }

  void _save() {
    final strings = AppStrings.of(context);
    final title = _titleController.text.trim();
    final content = _contentController.text.trimRight();

    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.addTitleOrContent)));
      return;
    }

    Navigator.of(context).pop(
      NoteEditorResult(
        title: title.isEmpty ? strings.untitledNote : title,
        content: content,
      ),
    );
  }

  Future<void> _close() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }

    final strings = AppStrings.of(context);
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.discardChanges),
        content: Text(strings.unsavedWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.keepEditing),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.discard),
          ),
        ],
      ),
    );

    if (shouldDiscard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  TextSelection get _safeSelection {
    final selection = _contentController.selection;
    final textLength = _contentController.text.length;
    if (!selection.isValid ||
        selection.start < 0 ||
        selection.end > textLength) {
      return TextSelection.collapsed(offset: textLength);
    }
    return selection;
  }

  void _wrapSelection(String prefix, String suffix) {
    final value = _contentController.value;
    final selection = _safeSelection;
    final selected = value.text.substring(selection.start, selection.end);
    final replacement = '$prefix$selected$suffix';

    _contentController.value = value.copyWith(
      text: value.text.replaceRange(
        selection.start,
        selection.end,
        replacement,
      ),
      selection: selected.isEmpty
          ? TextSelection.collapsed(offset: selection.start + prefix.length)
          : TextSelection(
              baseOffset: selection.start + prefix.length,
              extentOffset: selection.end + prefix.length,
            ),
      composing: TextRange.empty,
    );
    _contentFocusNode.requestFocus();
  }

  void _prefixSelectedLines(String prefix) {
    final value = _contentController.value;
    final selection = _safeSelection;
    final lineStart = selection.start == 0
        ? 0
        : value.text.lastIndexOf('\n', selection.start - 1) + 1;
    final lineEndSearch = value.text.indexOf('\n', selection.end);
    final lineEnd = lineEndSearch == -1 ? value.text.length : lineEndSearch;
    final selectedLines = value.text.substring(lineStart, lineEnd);
    final replacement = selectedLines
        .split('\n')
        .map((line) => '$prefix$line')
        .join('\n');

    _contentController.value = value.copyWith(
      text: value.text.replaceRange(lineStart, lineEnd, replacement),
      selection: TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + replacement.length,
      ),
      composing: TextRange.empty,
    );
    _contentFocusNode.requestFocus();
  }

  int get _wordCount {
    final text = _contentController.text.trim();
    return text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _close();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
          const SingleActivator(LogicalKeyboardKey.escape): _close,
        },
        child: Scaffold(
          backgroundColor: colors.surfaceContainerLowest,
          appBar: AppBar(
            leading: IconButton(
              tooltip: strings.closeEditor,
              onPressed: _close,
              icon: const Icon(Icons.close),
            ),
            title: Text(_isEditing ? strings.editNote : strings.newNote),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: Text(strings.done),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 760;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 32 : 12,
                        isWide ? 24 : 6,
                        isWide ? 32 : 12,
                        12,
                      ),
                      child: Material(
                        color: isWide
                            ? colors.surfaceContainerLow
                            : colors.surfaceContainerLowest,
                        elevation: isWide ? 1 : 0,
                        borderRadius: BorderRadius.circular(isWide ? 28 : 18),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                isWide ? 32 : 16,
                                isWide ? 28 : 14,
                                isWide ? 32 : 16,
                                12,
                              ),
                              child: TextField(
                                controller: _titleController,
                                autofocus: !_isEditing,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                maxLines: 2,
                                minLines: 1,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                decoration: InputDecoration(
                                  hintText: strings.noteTitle,
                                  border: InputBorder.none,
                                  filled: false,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            _FormattingToolbar(
                              isPreview: _showPreview,
                              onPreviewToggle: () {
                                setState(() => _showPreview = !_showPreview);
                                if (!_showPreview) {
                                  _contentFocusNode.requestFocus();
                                }
                              },
                              onBold: () => _wrapSelection('**', '**'),
                              onItalic: () => _wrapSelection('_', '_'),
                              onHeading: () => _prefixSelectedLines('## '),
                              onBullet: () => _prefixSelectedLines('- '),
                              onNumbered: () => _prefixSelectedLines('1. '),
                              onChecklist: () => _prefixSelectedLines('- [ ] '),
                              onQuote: () => _prefixSelectedLines('> '),
                              onCode: () => _wrapSelection('`', '`'),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  isWide ? 32 : 16,
                                  18,
                                  isWide ? 32 : 16,
                                  12,
                                ),
                                child: _showPreview
                                    ? AnimatedBuilder(
                                        animation: _contentController,
                                        builder: (context, _) {
                                          final content = _contentController
                                              .text
                                              .trim();

                                          if (content.isEmpty) {
                                            return Align(
                                              alignment: Alignment.topLeft,
                                              child: Text(
                                                strings.writingHint,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.copyWith(
                                                      color: colors
                                                          .onSurfaceVariant,
                                                      height: 1.55,
                                                    ),
                                              ),
                                            );
                                          }

                                          return SingleChildScrollView(
                                            child: SizedBox(
                                              width: double.infinity,
                                              child: NoteMarkdown(
                                                data: _contentController.text,
                                                selectable: true,
                                                onTaskChanged: (updated) {
                                                  _contentController.text =
                                                      updated;
                                                },
                                              ),
                                            ),
                                          );
                                        },
                                      )
                                    : TextField(
                                        controller: _contentController,
                                        focusNode: _contentFocusNode,
                                        expands: true,
                                        minLines: null,
                                        maxLines: null,
                                        textAlignVertical:
                                            TextAlignVertical.top,
                                        keyboardType: TextInputType.multiline,
                                        textCapitalization:
                                            TextCapitalization.sentences,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(height: 1.55),
                                        decoration: InputDecoration(
                                          hintText: strings.writingHint,
                                          border: InputBorder.none,
                                          filled: false,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isWide ? 32 : 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainer,
                                border: Border(
                                  top: BorderSide(color: colors.outlineVariant),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isDirty
                                        ? Icons.edit_outlined
                                        : Icons.check_circle_outline,
                                    size: 16,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _isDirty
                                          ? strings.unsavedChanges
                                          : strings.noChangesYet,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  AnimatedBuilder(
                                    animation: _contentController,
                                    builder: (context, _) => Text(
                                      strings.wordCount(_wordCount),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FormattingToolbar extends StatelessWidget {
  const _FormattingToolbar({
    required this.isPreview,
    required this.onPreviewToggle,
    required this.onBold,
    required this.onItalic,
    required this.onHeading,
    required this.onBullet,
    required this.onNumbered,
    required this.onChecklist,
    required this.onQuote,
    required this.onCode,
  });

  final bool isPreview;
  final VoidCallback onPreviewToggle;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onHeading;
  final VoidCallback onBullet;
  final VoidCallback onNumbered;
  final VoidCallback onChecklist;
  final VoidCallback onQuote;
  final VoidCallback onCode;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        children: [
          _EditorTool(
            tooltip: isPreview ? strings.editMarkdown : strings.previewMarkdown,
            icon: isPreview ? Icons.edit_outlined : Icons.visibility_outlined,
            onPressed: onPreviewToggle,
          ),
          const VerticalDivider(indent: 6, endIndent: 6),
          _EditorTool(
            tooltip: strings.heading,
            icon: Icons.title,
            onPressed: onHeading,
          ),
          _EditorTool(
            tooltip: strings.bold,
            icon: Icons.format_bold,
            onPressed: onBold,
          ),
          _EditorTool(
            tooltip: strings.italic,
            icon: Icons.format_italic,
            onPressed: onItalic,
          ),
          const VerticalDivider(indent: 6, endIndent: 6),
          _EditorTool(
            tooltip: strings.bulletedList,
            icon: Icons.format_list_bulleted,
            onPressed: onBullet,
          ),
          _EditorTool(
            tooltip: strings.numberedList,
            icon: Icons.format_list_numbered,
            onPressed: onNumbered,
          ),
          _EditorTool(
            tooltip: strings.checklist,
            icon: Icons.checklist,
            onPressed: onChecklist,
          ),
          const VerticalDivider(indent: 6, endIndent: 6),
          _EditorTool(
            tooltip: strings.quote,
            icon: Icons.format_quote,
            onPressed: onQuote,
          ),
          _EditorTool(
            tooltip: strings.inlineCode,
            icon: Icons.code,
            onPressed: onCode,
          ),
        ],
      ),
    );
  }
}

class _EditorTool extends StatelessWidget {
  const _EditorTool({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}
