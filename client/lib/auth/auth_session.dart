class AuthSession {
  const AuthSession({
    required this.email,
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.refreshSessionId,
  });

  final String email;
  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
  final String refreshSessionId;

  bool get isAccessTokenExpired =>
      DateTime.now().toUtc().isAfter(accessTokenExpiresAt.toUtc());

  bool get isRefreshTokenExpired =>
      DateTime.now().toUtc().isAfter(refreshTokenExpiresAt.toUtc());

  AuthSession copyWith({
    String? email,
    String? accessToken,
    DateTime? accessTokenExpiresAt,
    String? refreshToken,
    DateTime? refreshTokenExpiresAt,
    String? refreshSessionId,
  }) {
    return AuthSession(
      email: email ?? this.email,
      accessToken: accessToken ?? this.accessToken,
      accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
      refreshToken: refreshToken ?? this.refreshToken,
      refreshTokenExpiresAt:
          refreshTokenExpiresAt ?? this.refreshTokenExpiresAt,
      refreshSessionId: refreshSessionId ?? this.refreshSessionId,
    );
  }

  factory AuthSession.fromLoginResponse({required Map<String, dynamic> json}) {
    return AuthSession(
      email: _requiredString(json, 'email'),
      accessToken: _requiredString(json, 'accessToken'),
      accessTokenExpiresAt: DateTime.parse(
        _requiredString(json, 'accessTokenExpiresAt'),
      ).toUtc(),
      refreshToken: _requiredString(json, 'refreshToken'),
      refreshTokenExpiresAt: DateTime.parse(
        _requiredString(json, 'refreshTokenExpiresAt'),
      ).toUtc(),
      refreshSessionId: _requiredString(json, 'refreshSessionId'),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];

    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Authentication response is missing "$key".');
    }

    return value;
  }
}
