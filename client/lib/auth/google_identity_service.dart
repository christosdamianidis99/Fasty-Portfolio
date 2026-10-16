import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/api_endpoint.dart';
import 'google_identity_desktop_stub.dart'
    if (dart.library.io) 'google_identity_desktop_io.dart'
    as desktop;

abstract class GoogleIdentityService {
  bool get isAvailable;
  String? get unavailableReason;
  Future<String?> acquireIdToken();
}

class DefaultGoogleIdentityService implements GoogleIdentityService {
  DefaultGoogleIdentityService._();

  static final instance = DefaultGoogleIdentityService._();

  static const _androidServerClientId = String.fromEnvironment(
    'FASTY_GOOGLE_SERVER_CLIENT_ID',
  );
  static const _desktopClientId = String.fromEnvironment(
    'FASTY_GOOGLE_DESKTOP_CLIENT_ID',
  );

  Future<void>? _androidInitialization;

  @override
  bool get isAvailable {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidServerClientId.isNotEmpty,
      TargetPlatform.windows ||
      TargetPlatform.linux => _desktopClientId.isNotEmpty,
      _ => false,
    };
  }

  @override
  String? get unavailableReason {
    if (isAvailable) return null;
    if (kIsWeb) return 'Google sign-in is available on Android and desktop.';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Google sign-in is not configured for Android.',
      TargetPlatform.windows ||
      TargetPlatform.linux => 'Google sign-in is not configured for desktop.',
      _ => 'Google sign-in is unavailable on this device.',
    };
  }

  @override
  Future<String?> acquireIdToken() async {
    if (!isAvailable) {
      throw StateError(unavailableReason ?? 'Google sign-in is unavailable.');
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final signIn = GoogleSignIn.instance;
      await (_androidInitialization ??= signIn.initialize(
        serverClientId: _androidServerClientId,
      ));
      try {
        final account = await signIn.authenticate();
        final token = account.authentication.idToken;
        if (token == null || token.isEmpty) {
          throw StateError('Google did not return an identity token.');
        }
        return token;
      } on GoogleSignInException catch (error) {
        if (error.code == GoogleSignInExceptionCode.canceled) return null;
        rethrow;
      }
    }

    return desktop.acquireDesktopGoogleIdToken(
      _desktopClientId,
      apiBaseUrl: resolveApiBaseUrl(),
    );
  }
}
