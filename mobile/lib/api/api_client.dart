// Shared HTTP layer for the patient app.
//
// One place owns: base URL, bearer token, timeouts, JSON encoding, multipart
// upload, and error mapping. Auth (`auth.dart`) and result sync (`sync.dart`)
// previously hand-rolled their own POSTs; new screens go through this so 401
// refresh and offline classification behave identically everywhere.
//
// Responses from this backend are plain dicts (few v1 routes declare a
// response_model), so callers must parse defensively — see models.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Classification of a failed request, so screens can choose the right copy
/// and decide whether a retry is worthwhile.
enum ApiErrorKind {
  /// 401 — token missing, expired, or rejected.
  unauthorized,

  /// No connectivity / transport failure / timeout. Retryable.
  offline,

  /// 403 — authenticated but not allowed.
  forbidden,

  /// 404 — no such resource (or route not deployed at this base URL).
  notFound,

  /// 413 — payload too large (upload cap).
  tooLarge,

  /// 422 — schema validation failed; `problems` carries the details.
  validation,

  /// 5xx or any other unexpected status.
  server,
}

/// A failed API call. `message` is user-presentable.
class ApiException implements Exception {
  ApiException(
    this.kind,
    this.message, {
    this.statusCode,
    this.problems = const [],
    this.uri,
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;

  /// Field-level problems returned by the v2 ingest validator, when present.
  final List<String> problems;

  final Uri? uri;

  bool get isRetryable =>
      kind == ApiErrorKind.offline || kind == ApiErrorKind.server;

  @override
  String toString() =>
      'ApiException($kind${statusCode == null ? '' : ' $statusCode'}): $message';
}

/// Signature for the silent re-auth hook. Returns a fresh token or null.
typedef TokenRefresher = Future<String?> Function();

class ApiClient {
  ApiClient({
    required String baseUrl,
    this.tokenProvider,
    this.onUnauthorized,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.heavyTimeout = const Duration(seconds: 240),
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  /// Backend origin, no trailing slash and no `/api` suffix.
  final String baseUrl;

  /// Reads the current bearer token. Assignable so the session owner can push
  /// a refreshed token in without rebuilding the client.
  String? Function()? tokenProvider;

  /// Silent re-auth, attempted at most once per request on a 401.
  TokenRefresher? onUnauthorized;

  final http.Client _client;

  /// Default deadline for ordinary reads/writes.
  final Duration timeout;

  /// Deadline for endpoints that run OCR/CV/NLP/T5 inline (upload, analyze).
  final Duration heavyTimeout;

  String get _root => baseUrl;

  Future<dynamic> getJson(String path, {Duration? timeout}) =>
      _send('GET', path, timeout: timeout);

  Future<dynamic> postJson(String path, Object? body, {Duration? timeout}) =>
      _send('POST', path, body: body, timeout: timeout);

  Future<dynamic> putJson(String path, Object? body, {Duration? timeout}) =>
      _send('PUT', path, body: body, timeout: timeout);

  Future<dynamic> deleteJson(String path, {Duration? timeout}) =>
      _send('DELETE', path, timeout: timeout);

  /// Multipart upload. Defaults to the heavy timeout because the v1 upload
  /// route runs the full OCR/NLP/CV/summarize pipeline inline.
  Future<dynamic> postMultipart(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    String? contentType,
    Map<String, String>? fields,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$_root$path');
    final request = http.MultipartRequest('POST', uri);
    final token = tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (fields != null) request.fields.addAll(fields);
    request.files.add(
      http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: filename,
        contentType: contentType == null ? null : _parseMediaType(contentType),
      ),
    );

    http.Response response;
    try {
      final streamed = await _client
          .send(request)
          .timeout(timeout ?? heavyTimeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(
        ApiErrorKind.offline,
        'The server took too long to respond. It may be starting up — try again.',
        uri: uri,
      );
    } catch (_) {
      throw ApiException(
        ApiErrorKind.offline,
        'Cannot reach the backend at $baseUrl. Check your connection.',
        uri: uri,
      );
    }

    return _handle(uri, response);
  }

  // ---------------------------------------------------------------------
  // internals
  // ---------------------------------------------------------------------

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$_root$path');
    final headers = <String, String>{'Accept': 'application/json'};
    final token = tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    http.Response response;
    try {
      response = await _dispatch(method, uri, headers, body)
          .timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw ApiException(
        ApiErrorKind.offline,
        'The server took too long to respond. It may be starting up — try again.',
        uri: uri,
      );
    } on SocketException {
      throw ApiException(
        ApiErrorKind.offline,
        'Cannot reach the backend at $baseUrl. Check your connection.',
        uri: uri,
      );
    } on http.ClientException {
      throw ApiException(
        ApiErrorKind.offline,
        'Cannot reach the backend at $baseUrl. Check your connection.',
        uri: uri,
      );
    }

    // Expired session: try exactly one silent re-auth, then replay once.
    // No loops — a second 401 means the session is genuinely gone.
    if (response.statusCode == 401 && onUnauthorized != null) {
      final fresh = await _refresh();
      if (fresh != null && fresh.isNotEmpty) {
        headers['Authorization'] = 'Bearer $fresh';
        try {
          response = await _dispatch(method, uri, headers, body)
              .timeout(timeout ?? this.timeout);
        } on TimeoutException {
          throw ApiException(
            ApiErrorKind.offline,
            'The server took too long to respond.',
            uri: uri,
          );
        } catch (_) {
          throw ApiException(
            ApiErrorKind.offline,
            'Cannot reach the backend at $baseUrl. Check your connection.',
            uri: uri,
          );
        }
      }
    }

    return _handle(uri, response);
  }

  Future<http.Response> _dispatch(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) {
    final encoded = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(uri, headers: headers, body: encoded);
      case 'PUT':
        return _client.put(uri, headers: headers, body: encoded);
      case 'DELETE':
        return _client.delete(uri, headers: headers);
      default:
        throw ArgumentError('unsupported method $method');
    }
  }

  Future<String?> _refresh() async {
    try {
      return await onUnauthorized!.call();
    } catch (_) {
      return null;
    }
  }

  dynamic _handle(Uri uri, http.Response response) {
    final code = response.statusCode;

    if (code >= 200 && code < 300) {
      if (response.body.isEmpty) return null;
      try {
        return jsonDecode(response.body);
      } catch (_) {
        // Success with a non-JSON body (e.g. a file stream) — hand it back raw.
        return response.body;
      }
    }

    final detail = _extractDetail(response.body);

    switch (code) {
      case 401:
        throw ApiException(
          ApiErrorKind.unauthorized,
          'Your session has expired. Please sign in again.',
          statusCode: code,
          uri: uri,
        );
      case 403:
        throw ApiException(
          ApiErrorKind.forbidden,
          detail ?? 'You do not have access to this.',
          statusCode: code,
          uri: uri,
        );
      case 404:
        throw ApiException(
          ApiErrorKind.notFound,
          detail ?? 'Not found.',
          statusCode: code,
          uri: uri,
        );
      case 413:
        throw ApiException(
          ApiErrorKind.tooLarge,
          detail ?? 'File too large.',
          statusCode: code,
          uri: uri,
        );
      case 422:
        throw ApiException(
          ApiErrorKind.validation,
          detail ?? 'The server rejected the data sent.',
          statusCode: code,
          problems: _extractProblems(response.body),
          uri: uri,
        );
      default:
        throw ApiException(
          ApiErrorKind.server,
          detail ?? 'Something went wrong on the server ($code).',
          statusCode: code,
          uri: uri,
        );
    }
  }

  /// FastAPI errors are `{"detail": "..."}` or, for the v2 ingest validator,
  /// `{"detail": {"message": "...", "problems": [...]}}`.
  String? _extractDetail(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is Map) {
          final message = detail['message'];
          if (message is String) return message;
        }
      }
    } catch (_) {
      // Non-JSON error body.
    }
    return null;
  }

  List<String> _extractProblems(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] is Map) {
        final problems = (decoded['detail'] as Map)['problems'];
        if (problems is List) {
          return problems.map((p) => '$p').toList();
        }
      }
    } catch (_) {
      // Ignore.
    }
    return const [];
  }

  http.MediaType? _parseMediaType(String value) {
    final parts = value.split('/');
    if (parts.length != 2) return null;
    return http.MediaType(parts[0], parts[1]);
  }

  void close() => _client.close();
}
