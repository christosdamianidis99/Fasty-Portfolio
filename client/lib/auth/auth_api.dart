import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_session.dart';
import 'refresh_session_info.dart';

class AuthApi {
  AuthApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  static const _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client _client;

  Future<AuthSession> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    final normalizedEmail = email.trim();

    final response = await _send(
      _client.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({
          'email': normalizedEmail,
          'password': password,
          'deviceName': deviceName.trim(),
        }),
      ),
    );

    _ensureSuccess(response);

    return AuthSession.fromLoginResponse(json: _decodeObject(response));
  }

  Future<AuthSession> googleLogin({
    required String idToken,
    required String deviceName,
  }) async {
    final response = await _send(
      _client.post(
        Uri.parse('$baseUrl/api/auth/google'),
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({
          'idToken': idToken.trim(),
          'deviceName': deviceName.trim(),
        }),
      ),
    );

    _ensureSuccess(response);

    return AuthSession.fromLoginResponse(json: _decodeObject(response));
  }

  Future<bool> isGoogleLinked({required String accessToken}) async {
    final response = await _send(
      _client.get(
        Uri.parse('$baseUrl/api/auth/google/link'),
        headers: {
          'authorization': 'Bearer ${accessToken.trim()}',
          'accept': 'application/json',
        },
      ),
    );
    _ensureSuccess(response);
    final linked = _decodeObject(response)['linked'];
    if (linked is! bool) {
      throw const FormatException('Google link status is missing.');
    }
    return linked;
  }

  Future<String> linkGoogle({
    required String accessToken,
    required String idToken,
  }) async {
    final response = await _send(
      _client.post(
        Uri.parse('$baseUrl/api/auth/google/link'),
        headers: {
          'authorization': 'Bearer ${accessToken.trim()}',
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({'idToken': idToken.trim()}),
      ),
    );

    _ensureSuccess(response);

    return _decodeMessage(response);
  }

  Future<String> register({
    required String email,
    required String password,
  }) async {
    final response = await _send(
      _client.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({'email': email.trim(), 'password': password}),
      ),
    );

    if (response.statusCode == 404) {
      throw const AuthApiException(
        statusCode: 404,
        responseBody: '',
        fallbackMessage: 'Registration is currently unavailable.',
      );
    }

    _ensureSuccess(response);

    return _decodeMessage(response);
  }

  Future<String> confirmEmail({
    required String email,
    required String token,
  }) async {
    final response = await _send(
      _client.post(
        Uri.parse('$baseUrl/api/auth/confirm-email'),
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({'email': email.trim(), 'token': token.trim()}),
      ),
    );

    _ensureSuccess(response);

    return _decodeMessage(response);
  }

  Future<String> forgotPassword({required String email}) async {
    final response = await _send(
      _client.post(
        Uri.parse('$baseUrl/api/auth/forgot-password'),
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({'email': email.trim()}),
      ),
    );

    _ensureSuccess(response);

    return _decodeMessage(response);
  }

  Future<String> redeemPasswordRecoveryCredential({
    required String email,
    required String recoveryCredential,
    required String newPassword,
  }) async {
    final response = await _send(
      _client.post(
        Uri.parse('$baseUrl/api/auth/password-recovery/redeem'),
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({
          'email': email.trim(),
          'recoveryCredential': recoveryCredential.trim(),
          'newPassword': newPassword,
        }),
      ),
    );

    _ensureSuccess(response);

    return _decodeMessage(response);
  }

  Future<String> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    final response = await _send(
      _client.post(
        Uri.parse('$baseUrl/api/auth/reset-password'),
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({
          'email': email.trim(),
          'token': token.trim(),
          'newPassword': newPassword,
        }),
      ),
    );

    _ensureSuccess(response);

    return _decodeMessage(response);
  }

  Future<String> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _send(
      _client.post(
        Uri.parse('$baseUrl/api/auth/change-password'),
        headers: {
          'authorization': 'Bearer ${accessToken.trim()}',
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      ),
    );

    _ensureSuccess(response);

    return _decodeMessage(response);
  }

  Future<List<RefreshSessionInfo>> listSessions({
    required String accessToken,
  }) async {
    final response = await _send(
      _client.get(
        Uri.parse('$baseUrl/api/auth/sessions'),
        headers: {
          'authorization': 'Bearer ${accessToken.trim()}',
          'accept': 'application/json',
        },
      ),
    );

    _ensureSuccess(response);

    final decoded = jsonDecode(response.body);

    if (decoded is! List) {
      throw const FormatException('Invalid refresh session response.');
    }

    return decoded
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Invalid refresh session item.');
          }

          return RefreshSessionInfo.fromJson(item);
        })
        .toList(growable: false);
  }

  Future<void> revokeSession({
    required String accessToken,
    required String sessionId,
  }) async {
    final normalizedSessionId = sessionId.trim();

    if (normalizedSessionId.isEmpty) {
      throw const FormatException('Refresh session ID is required.');
    }

    final response = await _send(
      _client.delete(
        Uri.parse('$baseUrl/api/auth/sessions/$normalizedSessionId'),
        headers: {
          'authorization': 'Bearer ${accessToken.trim()}',
          'accept': 'application/json',
        },
      ),
    );

    _ensureSuccess(response);
  }

  Future<AuthSession> refresh(AuthSession currentSession) async {
    final response = await _send(
      _client.post(
        Uri.parse('$baseUrl/api/auth/refresh'),
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({'refreshToken': currentSession.refreshToken}),
      ),
    );

    _ensureSuccess(response);

    return AuthSession.fromLoginResponse(json: _decodeObject(response));
  }

  Future<void> logout(String refreshToken) async {
    final response = await _send(
      _client.post(
        Uri.parse('$baseUrl/api/auth/logout'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ),
    );

    _ensureSuccess(response);
  }

  Future<http.Response> _send(Future<http.Response> request) async {
    try {
      return await request.timeout(_requestTimeout);
    } on TimeoutException {
      throw AuthConnectionException(
        'The authentication server did not respond.',
      );
    } on http.ClientException catch (error) {
      throw AuthConnectionException(
        'Could not reach the authentication server: '
        '${error.message}',
      );
    }
  }

  String _decodeMessage(http.Response response) {
    final json = _decodeObject(response);
    final message = json['message'];

    if (message is! String || message.trim().isEmpty) {
      throw const FormatException('Invalid authentication response message.');
    }

    return message;
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid authentication response.');
    }

    return decoded;
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw AuthApiException(
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }

  void close() => _client.close();
}

class AuthConnectionException implements Exception {
  const AuthConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthApiException implements Exception {
  const AuthApiException({
    required this.statusCode,
    required this.responseBody,
    this.fallbackMessage,
  });

  final int statusCode;
  final String responseBody;
  final String? fallbackMessage;

  String? get code {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) return null;
      final value = decoded['code'];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    } on FormatException {
      return null;
    }
  }

  String? _readResponseMessage() {
    if (responseBody.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(responseBody);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final message = decoded['message'];

      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }

      final detail = decoded['detail'];

      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }

      final errors = decoded['errors'];

      if (errors is Map<String, dynamic>) {
        for (final value in errors.values) {
          if (value is List) {
            for (final error in value) {
              if (error is String && error.trim().isNotEmpty) {
                return error.trim();
              }
            }
          }

          if (value is String && value.trim().isNotEmpty) {
            return value.trim();
          }
        }
      }
    } on FormatException {
      return null;
    }

    return null;
  }

  @override
  String toString() {
    final responseMessage = _readResponseMessage();

    if (responseMessage != null) {
      return responseMessage;
    }

    if (fallbackMessage != null) {
      return fallbackMessage!;
    }

    if (statusCode == 401) {
      return 'The email or password is incorrect.';
    }

    if (statusCode == 423) {
      return 'The account is temporarily locked. '
          'Try again later.';
    }

    return 'Authentication failed ($statusCode).';
  }
}
