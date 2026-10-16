class PasswordResetLink {
  const PasswordResetLink({required this.email, required this.token});

  final String email;
  final String token;

  static PasswordResetLink? tryParse(Uri uri) {
    final normalizedPath = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;

    if (normalizedPath != '/reset-password') {
      return null;
    }

    final email = uri.queryParameters['email']?.trim() ?? '';

    final token = uri.queryParameters['token']?.trim() ?? '';

    if (email.isEmpty || token.isEmpty) {
      return null;
    }

    return PasswordResetLink(email: email, token: token);
  }
}
