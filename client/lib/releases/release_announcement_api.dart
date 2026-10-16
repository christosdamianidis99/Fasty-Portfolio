import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'release_announcement.dart';

class ReleaseAnnouncementApi {
  ReleaseAnnouncementApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  static const _requestTimeout = Duration(seconds: 12);

  final String baseUrl;
  final http.Client _client;

  Future<ReleaseAnnouncement?> fetchCurrent() async {
    late http.Response response;

    try {
      response = await _client
          .get(
            Uri.parse('$baseUrl/api/v1/release-announcement'),
            headers: const {'accept': 'application/json'},
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const ReleaseAnnouncementConnectionException(
        'Release announcement request timed out.',
      );
    } on http.ClientException catch (error) {
      throw ReleaseAnnouncementConnectionException(
        'Could not reach the release announcement service: '
        '${error.message}',
      );
    }

    if (response.statusCode == 204) {
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReleaseAnnouncementApiException(statusCode: response.statusCode);
    }

    final dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const FormatException(
        'Release announcement response is not valid JSON.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Release announcement response must be an object.',
      );
    }

    return ReleaseAnnouncement.fromJson(decoded);
  }

  void close() {
    _client.close();
  }
}

class ReleaseAnnouncementConnectionException implements Exception {
  const ReleaseAnnouncementConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReleaseAnnouncementApiException implements Exception {
  const ReleaseAnnouncementApiException({required this.statusCode});

  final int statusCode;

  @override
  String toString() {
    return 'Release announcement request failed '
        '($statusCode).';
  }
}
