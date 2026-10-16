import 'package:flutter/foundation.dart';

import 'auth_api.dart';
import 'auth_session.dart';
import 'auth_token_store.dart';
import 'refresh_session_info.dart';

enum AuthState { initializing, signedOut, signedIn }

class AuthController extends ChangeNotifier {
  AuthController({required AuthApi api, required AuthTokenStore tokenStore})
    : _api = api,
      _tokenStore = tokenStore;

  static const _refreshBeforeExpiry = Duration(seconds: 30);

  final AuthApi _api;
  final AuthTokenStore _tokenStore;

  AuthState _state = AuthState.initializing;
  AuthSession? _session;
  String? _errorMessage;
  String? _errorCode;
  String? _message;
  bool _busy = false;
  bool? _googleLinked;
  String? _googleLinkStatusError;
  Future<String?>? _refreshInProgress;

  AuthState get state => _state;
  AuthSession? get session => _session;
  String? get email => _session?.email;
  String? get accessToken => _session?.accessToken;
  String? get errorMessage => _errorMessage;
  String? get errorCode => _errorCode;
  String? get message => _message;
  bool get isBusy => _busy;
  bool get isSignedIn => _state == AuthState.signedIn;
  bool? get googleLinked => _googleLinked;
  String? get googleLinkStatusError => _googleLinkStatusError;

  Future<void> initialize() async {
    _errorMessage = null;
    _errorCode = null;

    final storedSession = await _tokenStore.load();

    if (storedSession == null || storedSession.isRefreshTokenExpired) {
      await _signOutLocally();
      return;
    }

    _session = storedSession;
    _googleLinked = null;

    final token = await getValidAccessToken();

    if (token == null) {
      return;
    }

    _state = AuthState.signedIn;
    notifyListeners();
    await refreshGoogleLinkStatus();
  }

  Future<String?> getValidAccessToken({bool forceRefresh = false}) async {
    final currentSession = _session;

    if (currentSession == null) {
      return null;
    }

    if (currentSession.isRefreshTokenExpired) {
      await _signOutLocally();
      return null;
    }

    final refreshThreshold = DateTime.now().toUtc().add(_refreshBeforeExpiry);

    final accessTokenStillValid = currentSession.accessTokenExpiresAt
        .toUtc()
        .isAfter(refreshThreshold);

    if (!forceRefresh && accessTokenStillValid) {
      return currentSession.accessToken;
    }

    final existingRefresh = _refreshInProgress;

    if (existingRefresh != null) {
      return existingRefresh;
    }

    final refresh = _refreshAccessToken(currentSession);
    _refreshInProgress = refresh;

    try {
      return await refresh;
    } finally {
      if (identical(_refreshInProgress, refresh)) {
        _refreshInProgress = null;
      }
    }
  }

  Future<String?> _refreshAccessToken(AuthSession currentSession) async {
    try {
      final refreshed = await _api.refresh(currentSession);

      if (_session?.refreshToken != currentSession.refreshToken) {
        return _session?.accessToken;
      }

      await _tokenStore.save(refreshed);

      _session = refreshed;
      _state = AuthState.signedIn;
      _errorMessage = null;
      _errorCode = null;
      notifyListeners();

      return refreshed.accessToken;
    } on AuthApiException catch (error) {
      if (error.statusCode == 401) {
        if (_session?.refreshToken == currentSession.refreshToken) {
          await _signOutLocally();
        }

        return null;
      }

      return currentSession.accessToken;
    } on AuthConnectionException {
      return currentSession.accessToken;
    } catch (_) {
      return currentSession.accessToken;
    }
  }

  Future<bool> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    if (_busy) {
      return false;
    }

    _busy = true;
    _errorMessage = null;
    _errorCode = null;
    _message = null;
    notifyListeners();

    try {
      final session = await _api.login(
        email: email,
        password: password,
        deviceName: deviceName,
      );

      await _tokenStore.save(session);

      _session = session;
      _googleLinked = null;
      _state = AuthState.signedIn;
      await refreshGoogleLinkStatus();
      return true;
    } on Object catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> googleLogin({
    required String idToken,
    required String deviceName,
  }) async {
    if (_busy) {
      return false;
    }

    _busy = true;
    _errorMessage = null;
    _errorCode = null;
    _message = null;
    notifyListeners();

    try {
      final session = await _api.googleLogin(
        idToken: idToken,
        deviceName: deviceName,
      );

      await _tokenStore.save(session);

      _session = session;
      _googleLinked = true;
      _state = AuthState.signedIn;
      await refreshGoogleLinkStatus();
      return true;
    } on AuthApiException catch (error) {
      _errorCode = error.code;
      _errorMessage = error.toString();
      return false;
    } on Object catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshGoogleLinkStatus() async {
    _googleLinked = null;
    _googleLinkStatusError = null;
    notifyListeners();
    final sessionId = _session?.refreshSessionId;
    final token = await getValidAccessToken();
    if (token == null || sessionId == null) return;
    try {
      final linked = await _api.isGoogleLinked(accessToken: token);
      if (!isSignedIn || _session?.refreshSessionId != sessionId) return;
      _googleLinked = linked;
      notifyListeners();
    } on AuthApiException catch (error) {
      if (!isSignedIn || _session?.refreshSessionId != sessionId) return;
      _googleLinkStatusError = error.statusCode == 405
          ? 'The server needs an update before it can check Google linking.'
          : 'Could not check Google linking (HTTP ${error.statusCode}).';
      notifyListeners();
    } catch (_) {
      if (!isSignedIn || _session?.refreshSessionId != sessionId) return;
      _googleLinkStatusError =
          'Could not contact the server to check Google linking.';
      notifyListeners();
    }
  }

  Future<bool> linkGoogle({required String idToken}) async {
    if (_busy) {
      return false;
    }

    _busy = true;
    _errorMessage = null;
    _errorCode = null;
    _message = null;
    notifyListeners();

    try {
      final token = await getValidAccessToken();

      if (token == null || token.trim().isEmpty) {
        _errorMessage = 'The authenticated session is no longer valid.';
        return false;
      }

      _message = await _api.linkGoogle(accessToken: token, idToken: idToken);
      _googleLinked = true;
      return true;
    } on AuthApiException catch (error) {
      _errorCode = error.code;
      _errorMessage = error.toString();
      return false;
    } on Object catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String email,
    required String password,
  }) async {
    if (_busy) {
      return false;
    }

    _busy = true;
    _errorMessage = null;
    _errorCode = null;
    _message = null;
    notifyListeners();

    try {
      _message = await _api.register(email: email, password: password);

      return true;
    } on Object catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> confirmEmail({
    required String email,
    required String token,
  }) async {
    if (_busy) {
      return false;
    }

    _busy = true;
    _errorMessage = null;
    _errorCode = null;
    _message = null;
    notifyListeners();

    try {
      _message = await _api.confirmEmail(email: email, token: token);

      return true;
    } on Object catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> forgotPassword({required String email}) async {
    if (_busy) {
      return false;
    }

    _busy = true;
    _errorMessage = null;
    _errorCode = null;
    _message = null;
    notifyListeners();

    try {
      _message = await _api.forgotPassword(email: email);

      return true;
    } on Object catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> redeemPasswordRecoveryCredential({
    required String email,
    required String recoveryCredential,
    required String newPassword,
  }) async {
    if (_busy) {
      return false;
    }

    _busy = true;
    _errorMessage = null;
    _errorCode = null;
    _message = null;
    notifyListeners();

    try {
      _message = await _api.redeemPasswordRecoveryCredential(
        email: email,
        recoveryCredential: recoveryCredential,
        newPassword: newPassword,
      );

      return true;
    } on Object catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    if (_busy) {
      return false;
    }

    _busy = true;
    _errorMessage = null;
    _errorCode = null;
    _message = null;
    notifyListeners();

    try {
      _message = await _api.resetPassword(
        email: email,
        token: token,
        newPassword: newPassword,
      );

      return true;
    } on Object catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_busy) {
      return false;
    }

    _busy = true;
    _errorMessage = null;
    _errorCode = null;
    _message = null;
    notifyListeners();

    try {
      final token = await getValidAccessToken();

      if (token == null || token.trim().isEmpty) {
        _errorMessage = 'The authenticated session is no longer valid.';
        return false;
      }

      _message = await _api.changePassword(
        accessToken: token,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      await _signOutLocally();

      return true;
    } on Object catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<List<RefreshSessionInfo>?> listSessions() async {
    if (_busy) {
      return null;
    }

    _busy = true;
    _errorMessage = null;
    _errorCode = null;
    _message = null;
    notifyListeners();

    try {
      final token = await getValidAccessToken();

      if (token == null || token.trim().isEmpty) {
        _errorMessage = 'The authenticated session is no longer valid.';
        return null;
      }

      return await _api.listSessions(accessToken: token);
    } on Object catch (error) {
      _errorMessage = error.toString();
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> revokeSession(String sessionId) async {
    if (_busy) {
      return false;
    }

    final normalizedSessionId = sessionId.trim();

    if (normalizedSessionId.isEmpty) {
      _errorMessage = 'Refresh session ID is required.';
      notifyListeners();
      return false;
    }

    _busy = true;
    _errorMessage = null;
    _errorCode = null;
    _message = null;
    notifyListeners();

    try {
      final token = await getValidAccessToken();

      if (token == null || token.trim().isEmpty) {
        _errorMessage = 'The authenticated session is no longer valid.';
        return false;
      }

      final revokesCurrentSession =
          _session?.refreshSessionId == normalizedSessionId;

      await _api.revokeSession(
        accessToken: token,
        sessionId: normalizedSessionId,
      );

      if (revokesCurrentSession) {
        await _signOutLocally();
      }

      return true;
    } on Object catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    if (_busy) {
      return;
    }

    _busy = true;
    _errorMessage = null;
    notifyListeners();

    final currentSession = _session;

    try {
      if (currentSession != null) {
        await _api.logout(currentSession.refreshToken);
      }
    } catch (_) {
      // Local logout must still succeed if the server is unavailable.
    } finally {
      await _signOutLocally();
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _signOutLocally() async {
    await _tokenStore.clear();

    _session = null;
    _googleLinked = null;
    _state = AuthState.signedOut;
    _errorMessage = null;
    _errorCode = null;

    notifyListeners();
  }

  void clearFeedback() {
    if (_errorMessage == null && _errorCode == null && _message == null) {
      return;
    }

    _errorMessage = null;
    _errorCode = null;
    _message = null;
    notifyListeners();
  }

  void clearError() {
    clearFeedback();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }
}
