// Patient repository routing tests, using a mocked HTTP client so no backend
// is needed. These lock the v2 lab-report paths the mobile app depends on.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intellimed_app/api/api_client.dart';
import 'package:intellimed_app/api/patient_repository.dart';

ApiClient _client(MockClient mock) =>
    ApiClient(baseUrl: 'http://localhost:8000', client: mock);

void main() {
  group('lab report routes', () {
    test('deleteLabReport issues DELETE to the report route', () async {
      String? method;
      Uri? uri;
      final repository = PatientRepository(
        _client(
          MockClient((request) async {
            method = request.method;
            uri = request.url;
            return http.Response('', 204);
          }),
        ),
      );

      await repository.deleteLabReport(42);

      expect(method, 'DELETE');
      expect(uri.toString(), 'http://localhost:8000/api/v2/lab-reports/42');
    });

    test('a 404 on delete surfaces as notFound, not a crash', () async {
      final repository = PatientRepository(
        _client(
          MockClient(
            (_) async =>
                http.Response('{"detail":"Lab report not found"}', 404),
          ),
        ),
      );

      await expectLater(
        repository.deleteLabReport(7),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.notFound,
          ),
        ),
      );
    });

    test('uploadLabReport posts multipart with source=app', () async {
      String? method;
      Uri? uri;
      String? contentType;
      String? body;
      final repository = PatientRepository(
        _client(
          MockClient((request) async {
            method = request.method;
            uri = request.url;
            contentType = request.headers['content-type'];
            body = request.body;
            return http.Response('{"id":1}', 201);
          }),
        ),
      );

      await repository.uploadLabReport(bytes: [1, 2, 3], filename: 'cbc.pdf');

      expect(method, 'POST');
      expect(uri.toString(), 'http://localhost:8000/api/v2/lab-reports/upload');
      expect(contentType, contains('multipart/form-data'));
      expect(body, contains('name="source"'));
      expect(body, contains('app'));
    });
  });
}
