import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'email_confirmation_link.dart';
import 'email_confirmation_page.dart';
import 'login_page.dart';
import 'password_reset_link.dart';
import 'reset_password_page.dart';

class SignedOutEntry extends StatefulWidget {
  const SignedOutEntry({
    super.key,
    required this.controller,
    this.initialConfirmationLink,
    this.initialPasswordResetLink,
    this.onConfirmationLinkPresented,
    this.onPasswordResetLinkPresented,
  });

  final AuthController controller;
  final EmailConfirmationLink? initialConfirmationLink;
  final PasswordResetLink? initialPasswordResetLink;
  final VoidCallback? onConfirmationLinkPresented;
  final VoidCallback? onPasswordResetLinkPresented;

  @override
  State<SignedOutEntry> createState() => _SignedOutEntryState();
}

class _SignedOutEntryState extends State<SignedOutEntry> {
  late bool _showConfirmation;
  late bool _showPasswordReset;
  String? _loginEmail;

  @override
  void initState() {
    super.initState();

    _showPasswordReset = widget.initialPasswordResetLink != null;

    _showConfirmation =
        !_showPasswordReset && widget.initialConfirmationLink != null;

    if (_showPasswordReset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onPasswordResetLinkPresented?.call();
      });
    } else if (_showConfirmation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onConfirmationLinkPresented?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final resetLink = widget.initialPasswordResetLink;

    if (_showPasswordReset && resetLink != null) {
      return ResetPasswordPage(
        controller: widget.controller,
        initialEmail: resetLink.email,
        initialToken: resetLink.token,
        onBack: () {
          setState(() {
            _showPasswordReset = false;
          });
        },
      );
    }

    final link = widget.initialConfirmationLink;

    if (_showConfirmation && link != null) {
      return EmailConfirmationPage(
        controller: widget.controller,
        initialEmail: link.email,
        initialToken: link.token,
        onBack: () {
          setState(() {
            _showConfirmation = false;
          });
        },
        onConfirmed: (email) {
          widget.controller.clearFeedback();

          setState(() {
            _loginEmail = email;
            _showConfirmation = false;
          });
        },
      );
    }

    return LoginPage(controller: widget.controller, initialEmail: _loginEmail);
  }
}
