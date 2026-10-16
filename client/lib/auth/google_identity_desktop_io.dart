import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

String _randomUrlToken() {
  final random = Random.secure();
  return base64Url
      .encode(List<int>.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

Future<String?> acquireDesktopGoogleIdToken(
  String clientId, {
  required String apiBaseUrl,
  Future<bool> Function(Uri)? openBrowser,
  http.Client? client,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final redirectUri = Uri.parse('http://127.0.0.1:${server.port}/');
  final state = _randomUrlToken();
  final verifier = _randomUrlToken();
  final challenge = base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  final authorizationUri =
      Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirectUri.toString(),
        'response_type': 'code',
        'scope': 'openid email profile',
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      });

  final result = Completer<String?>();
  final subscription = server.listen((request) async {
    if (request.uri.path != '/' ||
        request.uri.queryParameters['state'] != state) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final parameters = request.uri.queryParameters;

    request.response.headers.contentType = ContentType.html;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.write(
      '<!doctype html><meta charset="utf-8"><title>Fasty</title>'
      '<p>You can close this tab and return to Fasty.</p>',
    );
    await request.response.close();

    if (!result.isCompleted) {
      if (parameters['error'] == 'access_denied') {
        result.complete(null);
      } else if (parameters['code'] case final String code) {
        result.complete(code);
      } else {
        result.completeError(
          StateError('Google sign-in did not return a code.'),
        );
      }
    }
  });

  final exchangeClient = client ?? http.Client();

  try {
    final launched =
        await (openBrowser?.call(authorizationUri) ??
            launchUrl(authorizationUri, mode: LaunchMode.externalApplication));

    if (!launched) {
      throw StateError('Could not open the browser for Google sign-in.');
    }

    final code = await result.future.timeout(const Duration(minutes: 2));
    if (code == null) return null;

    var normalizedApiBaseUrl = apiBaseUrl.trim();

    while (normalizedApiBaseUrl.endsWith('/')) {
      normalizedApiBaseUrl = normalizedApiBaseUrl.substring(
        0,
        normalizedApiBaseUrl.length - 1,
      );
    }

    final response = await exchangeClient
        .post(
          Uri.parse('$normalizedApiBaseUrl/api/auth/google/desktop/exchange'),
          headers: const {
            HttpHeaders.contentTypeHeader: 'application/json',
            HttpHeaders.acceptHeader: 'application/json',
          },
          body: jsonEncode({
            'code': code,
            'codeVerifier': verifier,
            'redirectUri': redirectUri.toString(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw StateError('Google sign-in could not finish.');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic> ||
        decoded['idToken'] is! String ||
        (decoded['idToken'] as String).isEmpty) {
      throw const FormatException(
        'Fasty did not return a Google identity token.',
      );
    }

    return decoded['idToken'] as String;
  } finally {
    await subscription.cancel();
    await server.close(force: true);

    if (client == null) {
      exchangeClient.close();
    }
  }
}
