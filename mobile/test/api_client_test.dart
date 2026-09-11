import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intellimed_app/api/api_client.dart';

ApiClient _client(
  MockClient mock, {
  String? Function()? token,
  TokenRefresher? refresh,
}) => ApiClient(
  baseUrl: 'http://localhost:8000',
  client: mock,
  tokenProvider: token,
  onUnauthorized: refresh,
);

void main() {
  group('success', () {
    test('decodes a JSON body', () async {
      final client = _client(
        MockClient((_) async => http.Response(jsonEncode({'id': 7}), 200)),
      );
      final decoded = await client.getJson('/api/v2/lab-reports');
      expect((decoded as Map)['id'], 7);
    });

    test('returns null for an empty 204 body', () async {
      final client = _client(MockClient((_) async => http.Response('', 204)));
      expect(await client.deleteJson('/x'), isNull);
    });

    test('sends the bearer token when one is available', () async {
      String? seen;
      final client = _client(
        MockClient((request) async {
          seen = request.headers['Authorization'];
          return http.Response('{}', 200);
        }),
        token: () => 'jwt-abc',
      );
      await client.getJson('/api/v1/profile');
      expect(seen, 'Bearer jwt-abc');
    });

    test('omits the header when there is no token', () async {
      String? seen;
      final client = _client(
        MockClient((request) async {
          seen = request.headers['Authorization'];
          return http.Response('{}', 200);
        }),
      );
      await client.getJson('/api/v1/profile');
      expect(seen, isNull);
    });
  });

  group('error mapping', () {
    Future<ApiException> failure(int status, [String body = '{}']) async {
      final client = _client(MockClient((_) async => http.Response(body, status)));
      try {
        await client.getJson('/x');
        fail('expected ApiException');
      } on ApiException catch (e) {
        return e;
      }
    }

    test('401 -> unauthorized', () async {
      expect((await failure(401)).kind, ApiErrorKind.unauthorized);
    });

    test('403 -> forbidden', () async {
      expect((await failure(403)).kind, ApiErrorKind.forbidden);
    });

    test('404 -> notFound', () async {
      expect((await failure(404)).kind, ApiErrorKind.notFound);
    });

    test('413 -> tooLarge', () async {
      expect((await failure(413)).kind, ApiErrorKind.tooLarge);
    });

    test('500 -> server and retryable', () async {
      final e = await failure(500);
      expect(e.kind, ApiErrorKind.server);
      expect(e.isRetryable, isTrue);
    });

    test('offline is retryable, validation is not', () async {
      final client = _client(
        MockClient((_) async => throw http.ClientException('no route')),
      );
      try {
        await client.getJson('/x');
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.kind, ApiErrorKind.offline);
        expect(e.isRetryable, isTrue);
      }

      final validation = await failure(422);
      expect(validation.kind, ApiErrorKind.validation);
      expect(validation.isRetryable, isFalse);
    });

    test('a plain string detail becomes the message', () async {
      final e = await failure(
        400,
        jsonEncode({'detail': 'Incorrect email or password'}),
      );
      expect(e.message, 'Incorrect email or password');
    });

    test('422 surfaces the nested validate_ingest_payload problems', () async {
      final e = await failure(
        422,
        jsonEncode({
          'detail': {
            'message': 'Structured result failed schema validation',
            'problems': [
              'test \'Hb\' carries Stage 3 fields (abnormal/direction)',
            ],
          },
        }),
      );
      expect(e.message, 'Structured result failed schema validation');
      expect(e.problems, hasLength(1));
      expect(e.problems.first, contains('Stage 3 fields'));
    });

    test('a non-JSON error body does not crash the mapper', () async {
      final e = await failure(500, '<html>gateway error</html>');
      expect(e.kind, ApiErrorKind.server);
      expect(e.message, isNotEmpty);
    });
  });

  group('401 recovery', () {
    test('refreshes once and replays with the new token', () async {
      final tokens = <String?>[];
      var calls = 0;
      final client = _client(
        MockClient((request) async {
          tokens.add(request.headers['Authorization']);
          calls++;
          if (calls == 1) return http.Response('{}', 401);
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
        token: () => 'stale',
        refresh: () async => 'fresh',
      );

      final decoded = await client.getJson('/api/v1/profile');
      expect((decoded as Map)['ok'], isTrue);
      expect(calls, 2);
      expect(tokens.first, 'Bearer stale');
      expect(tokens.last, 'Bearer fresh');
    });

    test('gives up after a second 401 without looping', () async {
      var calls = 0;
      final client = _client(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 401);
        }),
        token: () => 'stale',
        refresh: () async => 'fresh',
      );

      await expectLater(
        client.getJson('/x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.unauthorized,
          ),
        ),
      );
      expect(calls, 2);
    });

    test('a failing refresh surfaces unauthorized', () async {
      var calls = 0;
      final client = _client(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 401);
        }),
        token: () => 'stale',
        refresh: () async => null,
      );

      await expectLater(
        client.getJson('/x'),
        throwsA(isA<ApiException>()),
      );
      // No token came back, so the request is not replayed.
      expect(calls, 1);
    });

    test('a throwing refresh is swallowed, not propagated', () async {
      final client = _client(
        MockClient((_) async => http.Response('{}', 401)),
        token: () => 'stale',
        refresh: () async => throw StateError('boom'),
      );

      await expectLater(
        client.getJson('/x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.unauthorized,
          ),
        ),
      );
    });
  });
}
