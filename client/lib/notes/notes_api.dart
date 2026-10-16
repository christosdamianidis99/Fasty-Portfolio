import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'note.dart';
import 'workspace_state.dart';

typedef AccessTokenProvider = Future<String?> Function({bool forceRefresh});

class NotesApi {
  NotesApi({
    required this.baseUrl,
    AccessTokenProvider? accessTokenProvider,
    http.Client? client,
  }) : _accessTokenProvider = accessTokenProvider,
       _client = client ?? http.Client();

  static const _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final AccessTokenProvider? _accessTokenProvider;
  final http.Client _client;

  Future<List<Note>> listNotes() async {
    final response = await _sendAuthenticated(
      (headers) =>
          _client.get(Uri.parse('$baseUrl/api/v1/notes'), headers: headers),
    );

    _ensureSuccess(response);

    final body = jsonDecode(response.body) as List<dynamic>;

    return body
        .map((item) => Note.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Note> createNote({
    required String title,
    required String content,
  }) async {
    final body = jsonEncode({'title': title, 'content': content});

    final response = await _sendAuthenticated(
      (headers) => _client.post(
        Uri.parse('$baseUrl/api/v1/notes'),
        headers: {...headers, 'content-type': 'application/json'},
        body: body,
      ),
    );

    _ensureSuccess(response);

    return Note.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Note> upsertNote({
    required String id,
    required String title,
    required String content,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final body = jsonEncode({
      'title': title,
      'content': content,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    });

    final response = await _sendAuthenticated(
      (headers) => _client.put(
        Uri.parse('$baseUrl/api/v1/notes/$id'),
        headers: {...headers, 'content-type': 'application/json'},
        body: body,
      ),
    );

    _ensureSuccess(response);

    return Note.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Note> updateNote({
    required String id,
    required String title,
    required String content,
  }) async {
    final body = jsonEncode({'title': title, 'content': content});

    final response = await _sendAuthenticated(
      (headers) => _client.put(
        Uri.parse('$baseUrl/api/v1/notes/$id'),
        headers: {...headers, 'content-type': 'application/json'},
        body: body,
      ),
    );

    _ensureSuccess(response);

    return Note.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteNote({
    required String id,
    required DateTime updatedAt,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/notes/$id').replace(
      queryParameters: {'updatedAt': updatedAt.toUtc().toIso8601String()},
    );

    final response = await _sendAuthenticated(
      (headers) => _client.delete(uri, headers: headers),
    );

    _ensureSuccess(response);
  }

  Future<WorkspaceStateDocument?> getWorkspaceState() async {
    final response = await _sendAuthenticated(
      (headers) => _client.get(
        Uri.parse('$baseUrl/api/v1/workspace-state'),
        headers: headers,
      ),
    );

    _ensureSuccess(response);

    if (response.statusCode == 204 || response.body.trim().isEmpty) {
      return null;
    }

    return WorkspaceStateDocument.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<WorkspaceStateDocument> upsertWorkspaceState(
    WorkspaceStateDocument state,
  ) async {
    final body = jsonEncode(state.toJson());

    final response = await _sendAuthenticated(
      (headers) => _client.put(
        Uri.parse('$baseUrl/api/v1/workspace-state'),
        headers: {...headers, 'content-type': 'application/json'},
        body: body,
      ),
    );

    _ensureSuccess(response);

    return WorkspaceStateDocument.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<http.Response> _sendAuthenticated(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    final firstToken = await _accessTokenProvider?.call(forceRefresh: false);

    final firstResponse = await _send(request(_headers(firstToken)));

    if (firstResponse.statusCode != 401 || _accessTokenProvider == null) {
      return firstResponse;
    }

    final refreshedToken = await _accessTokenProvider.call(forceRefresh: true);

    if (refreshedToken == null || refreshedToken.trim().isEmpty) {
      throw const NotesAuthenticationException(
        'The authenticated session is no longer valid.',
      );
    }

    final retryResponse = await _send(request(_headers(refreshedToken)));

    return retryResponse;
  }

  Map<String, String> _headers(String? token) {
    final normalizedToken = token?.trim();

    return {
      if (normalizedToken != null && normalizedToken.isNotEmpty)
        'authorization': 'Bearer $normalizedToken',
      'accept': 'application/json',
    };
  }

  Future<http.Response> _send(Future<http.Response> request) async {
    try {
      return await request.timeout(_requestTimeout);
    } on TimeoutException {
      throw NotesConnectionException(
        'The sync server at $baseUrl did not respond '
        'within ${_requestTimeout.inSeconds} seconds.',
      );
    } on http.ClientException catch (error) {
      throw NotesConnectionException(
        'Could not reach the sync server at $baseUrl. '
        'Details: ${error.message}',
      );
    }
  }

  void close() => _client.close();

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode == 401) {
      throw const NotesAuthenticationException(
        'The authenticated session is no longer valid.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NotesApiException(
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }
}

class NotesConnectionException implements Exception {
  const NotesConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NotesAuthenticationException implements Exception {
  const NotesAuthenticationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NotesApiException implements Exception {
  const NotesApiException({
    required this.statusCode,
    required this.responseBody,
  });

  final int statusCode;
  final String responseBody;

  @override
  String toString() {
    final response = responseBody.trim();
    final details = response.isEmpty ? '' : ' â€” $response';

    return 'Notes API request failed '
        '($statusCode)$details';
  }
}
