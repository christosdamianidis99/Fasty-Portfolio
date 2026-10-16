import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'forgot_password_page.dart';
import 'google_identity_service.dart';
import 'registration_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.controller,
    this.initialEmail,
    this.googleIdentityService,
  });

  final AuthController controller;
  final String? initialEmail;
  final GoogleIdentityService? googleIdentityService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _googleBusy = false;
  String? _googleError;

  GoogleIdentityService get _googleIdentityService =>
      widget.googleIdentityService ?? DefaultGoogleIdentityService.instance;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: widget.initialEmail?.trim() ?? '',
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    await widget.controller.login(
      email: _emailController.text,
      password: _passwordController.text,
      deviceName: _deviceName(),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleBusy = true;
      _googleError = null;
    });
    widget.controller.clearFeedback();

    try {
      final idToken = await _googleIdentityService.acquireIdToken();
      if (idToken == null) return;
      await widget.controller.googleLogin(
        idToken: idToken,
        deviceName: _deviceName(),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _googleError = error.toString());
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  String _deviceName() {
    if (kIsWeb) {
      return 'Fasty Web';
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Fasty Android',
      TargetPlatform.iOS => 'Fasty iOS',
      TargetPlatform.windows => 'Fasty Windows',
      TargetPlatform.macOS => 'Fasty macOS',
      TargetPlatform.linux => 'Fasty Linux',
      TargetPlatform.fuchsia => 'Fasty',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
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
                            Icons.dashboard_rounded,
                            size: 48,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Welcome to Fasty',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sign in to synchronize your notes and workspace.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _emailController,
                            enabled: !widget.controller.isBusy && !_googleBusy,
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
                            controller: _passwordController,
                            enabled: !widget.controller.isBusy && !_googleBusy,
                            obscureText: _obscurePassword,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Enter your password.';
                              }
                              return null;
                            },
                          ),
                          if (widget.controller.errorMessage != null ||
                              _googleError != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _googleError ?? widget.controller.errorMessage!,
                                style: TextStyle(
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                          if (widget.controller.errorCode ==
                              'account_link_required') ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Sign in with your password, then link Google in Settings.',
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: widget.controller.isBusy || _googleBusy
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
                                  : const Text('Sign in'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const ValueKey('google-sign-in-button'),
                            onPressed:
                                widget.controller.isBusy ||
                                    _googleBusy ||
                                    !_googleIdentityService.isAvailable
                                ? null
                                : _signInWithGoogle,
                            icon: const Icon(Icons.account_circle_outlined),
                            label: Text(
                              _googleBusy
                                  ? 'Opening Google sign-in…'
                                  : 'Continue with Google',
                            ),
                          ),
                          if (!_googleIdentityService.isAvailable) ...[
                            const SizedBox(height: 8),
                            Text(
                              _googleIdentityService.unavailableReason ??
                                  'Google sign-in is unavailable.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextButton(
                            key: const ValueKey('forgot-password-button'),
                            onPressed: widget.controller.isBusy || _googleBusy
                                ? null
                                : () async {
                                    widget.controller.clearFeedback();

                                    await Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => ForgotPasswordPage(
                                          controller: widget.controller,
                                          initialEmail: _emailController.text,
                                        ),
                                      ),
                                    );

                                    widget.controller.clearFeedback();
                                  },
                            child: const Text('Forgot password?'),
                          ),
                          const SizedBox(height: 4),
                          OutlinedButton(
                            onPressed: widget.controller.isBusy || _googleBusy
                                ? null
                                : () async {
                                    widget.controller.clearFeedback();
                                    final registeredEmail =
                                        await Navigator.of(
                                          context,
                                        ).push<String>(
                                          MaterialPageRoute(
                                            builder: (_) => RegistrationPage(
                                              controller: widget.controller,
                                            ),
                                          ),
                                        );

                                    if (registeredEmail != null) {
                                      _emailController.text = registeredEmail;
                                      _passwordController.clear();
                                    }

                                    widget.controller.clearFeedback();
                                  },
                            child: const Text('Create account'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Private beta: account verification and recovery '
                            'emails are temporarily disabled.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
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
