class EmailConfirmationLink {
  const EmailConfirmationLink({required this.email, required this.token});

  final String email;
  final String token;

  static EmailConfirmationLink? tryParse(Uri uri) {
    final normalizedPath = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;

    if (normalizedPath != '/confirm-email') {
      return null;
    }

    final email = uri.queryParameters['email']?.trim() ?? '';
    final token = uri.queryParameters['token']?.trim() ?? '';

    if (email.isEmpty || token.isEmpty) {
      return null;
    }

    return EmailConfirmationLink(email: email, token: token);
  }
}
