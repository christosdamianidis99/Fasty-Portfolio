import 'dart:convert';

import 'package:fasty/notes/notes_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'refreshes token and retries once after unauthorized response',
    () async {
      final requestedTokens = <String?>[];
      final refreshFlags = <bool>[];
      var requestCount = 0;

      final client = MockClient((request) async {
        requestCount++;
        requestedTokens.add(request.headers['authorization']);

        if (requestCount == 1) {
          return http.Response('', 401);
        }

        return http.Response(
          jsonEncode([
            {
              'id': 'note-1',
              'title': 'Refreshed note',
              'content': 'Loaded after token refresh.',
              'createdAt': '2026-07-28T12:00:00Z',
              'updatedAt': '2026-07-28T12:00:00Z',
              'isDeleted': false,
            },
          ]),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });

      final api = NotesApi(
        baseUrl: 'http://fasty.test',
        client: client,
        accessTokenProvider: ({bool forceRefresh = false}) async {
          refreshFlags.add(forceRefresh);

          return forceRefresh ? 'fresh-access-token' : 'expired-access-token';
        },
      );

      final notes = await api.listNotes();

      expect(requestCount, 2);
      expect(refreshFlags, [false, true]);
      expect(requestedTokens, [
        'Bearer expired-access-token',
        'Bearer fresh-access-token',
      ]);

      expect(notes, hasLength(1));
      expect(notes.single.id, 'note-1');
      expect(notes.single.title, 'Refreshed note');

      api.close();
    },
  );

  test(
    'does not retry more than once when refreshed token is rejected',
    () async {
      var requestCount = 0;
      var refreshCount = 0;

      final client = MockClient((request) async {
        requestCount++;
        return http.Response('', 401);
      });

      final api = NotesApi(
        baseUrl: 'http://fasty.test',
        client: client,
        accessTokenProvider: ({bool forceRefresh = false}) async {
          if (forceRefresh) {
            refreshCount++;
            return 'fresh-but-invalid-token';
          }

          return 'expired-token';
        },
      );

      await expectLater(
        api.listNotes(),
        throwsA(isA<NotesAuthenticationException>()),
      );

      expect(requestCount, 2);
      expect(refreshCount, 1);

      api.close();
    },
  );
}
