import 'package:flutter/material.dart';

import 'auth_controller.dart';

class EmailConfirmationPage extends StatefulWidget {
  const EmailConfirmationPage({
    super.key,
    required this.controller,
    this.initialEmail,
    this.initialToken,
    this.onBack,
    this.onConfirmed,
  });

  final AuthController controller;
  final String? initialEmail;
  final String? initialToken;
  final VoidCallback? onBack;
  final ValueChanged<String>? onConfirmed;

  @override
  State<EmailConfirmationPage> createState() => _EmailConfirmationPageState();
}

class _EmailConfirmationPageState extends State<EmailConfirmationPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _tokenController;

  @override
  void initState() {
    super.initState();

    _emailController = TextEditingController(
      text: widget.initialEmail?.trim() ?? '',
    );
    _tokenController = TextEditingController(
      text: widget.initialToken?.trim() ?? '',
    );

    widget.controller.clearFeedback();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final confirmed = await widget.controller.confirmEmail(
      email: _emailController.text,
      token: _tokenController.text,
    );

    if (!confirmed || !mounted) {
      return;
    }

    widget.onConfirmed?.call(_emailController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm email')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    return Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.mark_email_read_outlined,
                            size: 48,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Confirm your email address',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Enter the email address and confirmation token '
                            'from your verification message.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            key: const ValueKey('confirmation-email'),
                            controller: _emailController,
                            enabled: !widget.controller.isBusy,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (value) {
                              final email = value?.trim() ?? '';

                              if (email.isEmpty || !email.contains('@')) {
                                return 'Enter a valid email address.';
                              }

                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const ValueKey('confirmation-token'),
                            controller: _tokenController,
                            enabled: !widget.controller.isBusy,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(
                              labelText: 'Confirmation token',
                              prefixIcon: Icon(Icons.key_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter the confirmation token.';
                              }

                              return null;
                            },
                          ),
                          if (widget.controller.errorMessage != null) ...[
                            const SizedBox(height: 16),
                            _FeedbackPanel(
                              message: widget.controller.errorMessage!,
                              backgroundColor: colorScheme.errorContainer,
                              foregroundColor: colorScheme.onErrorContainer,
                            ),
                          ],
                          if (widget.controller.message != null) ...[
                            const SizedBox(height: 16),
                            _FeedbackPanel(
                              message: widget.controller.message!,
                              backgroundColor: colorScheme.primaryContainer,
                              foregroundColor: colorScheme.onPrimaryContainer,
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: widget.controller.isBusy
                                ? null
                                : _submit,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: widget.controller.isBusy
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Confirm email'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: widget.controller.isBusy
                                ? null
                                : () {
                                    widget.controller.clearFeedback();

                                    final onBack = widget.onBack;

                                    if (onBack != null) {
                                      onBack();
                                      return;
                                    }

                                    Navigator.of(context).maybePop();
                                  },
                            child: const Text('Back'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  const _FeedbackPanel({
    required this.message,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String message;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: foregroundColor)),
    );
  }
}
