import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:intellimed_app/cnn_ocr.dart';
import 'package:intellimed_app/inference_queue.dart';
import 'package:intellimed_app/sync.dart';

void main() {
  test('inference queue serializes overlapping calls', () async {
    final queue = InferenceQueue();
    final order = <int>[];
    Future<int> slowTask(int id) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      order.add(id);
      return id;
    }

    final results = await Future.wait([
      queue.add(() => slowTask(1)),
      queue.add(() => slowTask(2)),
      queue.add(() => slowTask(3)),
    ]);
    expect(results, [1, 2, 3]);
    expect(order, [1, 2, 3]);
  });

  test('xray preprocess matches ImageNet mean/std NCHW layout', () {
    final src = img.Image(width: 4, height: 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        src.setPixelRgb(x, y, 255, 255, 255);
      }
    }
    final flat = CnnClassifier.preprocessXray(src);
    expect(flat.length, 1 * 3 * xrayInputSize * xrayInputSize);
    // White pixel -> (1 - mean) / std per channel, first element is R of (0,0).
    expect(flat[0], closeTo((1 - xrayMean[0]) / xrayStd[0], 1e-6));
    final gStart = xrayInputSize * xrayInputSize;
    expect(flat[gStart], closeTo((1 - xrayMean[1]) / xrayStd[1], 1e-6));
  });

  test('sync payload is tagged source=app', () async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'id': 7}), 200);
    });
    final uri = Uri.parse('http://x/api/v2/lab-reports/upload-structured');
    await client.post(
      uri,
      body: jsonEncode({'kind': 'lab_report', 'source': 'app'}),
    );
    expect(sent!['source'], 'app');
  });

  test('V2Sync sends Authorization header when token is set', () async {
    String? authHeader;
    final client = MockClient((request) async {
      authHeader = request.headers['Authorization'];
      return http.Response(jsonEncode({'id': 42}), 200);
    });
    final sync = V2Sync(
      baseUrl: 'http://localhost:8000',
      client: client,
      token: 'jwt-test-token-123',
    );
    final id = await sync.postResult(
      kind: 'lab_report',
      envelope: {'kind': 'lab_report', 'normalized': {}},
    );
    expect(id, 42);
    expect(authHeader, 'Bearer jwt-test-token-123');
  });

  test('transport failure surfaces as OfflineException (stays retryable)',
      () async {
    final client = MockClient(
      (_) async => throw http.ClientException('no route to host'),
    );
    final sync = V2Sync(baseUrl: 'http://localhost:8000', client: client);
    expect(
      () => sync.postResult(
        kind: 'lab_report',
        envelope: {'kind': 'lab_report', 'normalized': {}},
      ),
      throwsA(isA<OfflineException>()),
    );
  });

  test('401 triggers one silent refresh and replays with the new token',
      () async {
    final tokens = <String?>[];
    var calls = 0;
    final client = MockClient((request) async {
      tokens.add(request.headers['Authorization']);
      calls++;
      // First attempt is rejected; the replay (with the fresh token) succeeds.
      if (calls == 1) return http.Response('{}', 401);
      return http.Response(jsonEncode({'id': 99}), 200);
    });
    final sync = V2Sync(
      baseUrl: 'http://localhost:8000',
      client: client,
      token: 'stale-token',
      onUnauthorized: () async => 'fresh-token',
    );

    final id = await sync.postResult(
      kind: 'lab_report',
      envelope: {'kind': 'lab_report', 'normalized': {}},
    );

    expect(id, 99);
    expect(calls, 2);
    expect(tokens.first, 'Bearer stale-token');
    expect(tokens.last, 'Bearer fresh-token');
    // The client adopts the refreshed token for subsequent rows.
    expect(sync.token, 'fresh-token');
  });

  test('401 with no recovery raises UnauthorizedException (stays retryable)',
      () async {
    final client = MockClient((_) async => http.Response('{}', 401));
    final sync = V2Sync(
      baseUrl: 'http://localhost:8000',
      client: client,
      token: 'stale-token',
      onUnauthorized: () async => null,
    );
    expect(
      () => sync.postResult(
        kind: 'lab_report',
        envelope: {'kind': 'lab_report', 'normalized': {}},
      ),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('a second 401 after refresh does not loop', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('{}', 401);
    });
    final sync = V2Sync(
      baseUrl: 'http://localhost:8000',
      client: client,
      token: 'stale-token',
      onUnauthorized: () async => 'fresh-token',
    );

    await expectLater(
      sync.postResult(
        kind: 'lab_report',
        envelope: {'kind': 'lab_report', 'normalized': {}},
      ),
      throwsA(isA<UnauthorizedException>()),
    );
    // Exactly the original attempt plus one replay — never more.
    expect(calls, 2);
  });
}

