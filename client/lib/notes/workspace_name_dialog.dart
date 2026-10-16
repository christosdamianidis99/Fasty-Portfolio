import 'package:flutter/material.dart';

class WorkspaceNameDialog extends StatefulWidget {
  const WorkspaceNameDialog({
    super.key,
    required this.title,
    required this.label,
    required this.cancelLabel,
    required this.confirmLabel,
    this.initialValue = '',
    this.hintText,
    this.icon,
  });

  final String title;
  final String label;
  final String cancelLabel;
  final String confirmLabel;
  final String initialValue;
  final String? hintText;
  final IconData? icon;

  @override
  State<WorkspaceNameDialog> createState() => _WorkspaceNameDialogState();
}

class _WorkspaceNameDialogState extends State<WorkspaceNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: widget.icon == null ? null : Icon(widget.icon),
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hintText,
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
