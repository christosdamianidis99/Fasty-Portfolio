import 'dart:convert';

import 'package:crypto/crypto.dart';

String accountDatabaseName(String email) {
  final normalizedEmail = email.trim().toLowerCase();

  if (normalizedEmail.isEmpty) {
    throw ArgumentError.value(email, 'email', 'Email must not be empty.');
  }

  final digest = sha256.convert(utf8.encode(normalizedEmail)).toString();

  return 'fasty_account_$digest';
}
