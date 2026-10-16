import 'dart:convert';

import 'package:fasty/releases/release_announcement.dart';
import 'package:fasty/releases/release_announcement_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses a complete release announcement', () {
    final announcement = ReleaseAnnouncement.fromJson({
      'id': ' release-2 ',
      'title': ' New beta ',
      'message': ' Please install the latest build. ',
      'contactUrl': ' mailto:christos@example.com ',
    });

    expect(announcement.id, 'release-2');
    expect(announcement.title, 'New beta');
    expect(announcement.message, 'Please install the latest build.');
    expect(announcement.contactUrl, 'mailto:christos@example.com');
  });

  test('normalizes empty contact URL to null', () {
    final announcement = ReleaseAnnouncement.fromJson({
      'id': 'release-2',
      'title': 'New beta',
      'message': 'Please update.',
      'contactUrl': '   ',
    });

    expect(announcement.contactUrl, isNull);
  });

  test('rejects missing required announcement fields', () {
    expect(
      () => ReleaseAnnouncement.fromJson({
        'id': 'release-2',
        'title': '',
        'message': 'Please update.',
      }),
      throwsFormatException,
    );
  });

  test('fetches current release announcement', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url,
        Uri.parse('http://fasty.test/api/v1/release-announcement'),
      );
      expect(request.headers['accept'], 'application/json');

      return http.Response(
        jsonEncode({
          'id': 'private-beta-refresh-1',
          'title': 'Fasty beta update',
          'message': 'A new beta build is available.',
          'contactUrl': 'mailto:christos@example.com',
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final api = ReleaseAnnouncementApi(
      baseUrl: 'http://fasty.test',
      client: client,
    );

    final announcement = await api.fetchCurrent();

    expect(announcement?.id, 'private-beta-refresh-1');
    expect(announcement?.title, 'Fasty beta update');
    expect(announcement?.contactUrl, 'mailto:christos@example.com');

    api.close();
  });

  test('returns null when no announcement is active', () async {
    final client = MockClient((_) async => http.Response('', 204));

    final api = ReleaseAnnouncementApi(
      baseUrl: 'http://fasty.test',
      client: client,
    );

    expect(await api.fetchCurrent(), isNull);

    api.close();
  });

  test('reports non-success release response', () async {
    final client = MockClient((_) async => http.Response('error', 503));

    final api = ReleaseAnnouncementApi(
      baseUrl: 'http://fasty.test',
      client: client,
    );

    await expectLater(
      api.fetchCurrent(),
      throwsA(
        isA<ReleaseAnnouncementApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          503,
        ),
      ),
    );

    api.close();
  });

  test('rejects malformed announcement response', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'id': 'release-2', 'title': 'New beta'}),
        200,
      ),
    );

    final api = ReleaseAnnouncementApi(
      baseUrl: 'http://fasty.test',
      client: client,
    );

    await expectLater(api.fetchCurrent(), throwsFormatException);

    api.close();
  });
}
