import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'store.dart';

/// Thrown when the v2 structured-ingest route isn't deployed where the app
/// points (HTTP 404). Rows in this state must stay `pending` — not `failed` —
/// so they sync once the backend is reachable instead of being written off.
class RouteMissingException implements Exception {
  RouteMissingException(this.uri);

  final Uri uri;

  @override
  String toString() => 'structured ingest route missing (404 at $uri)';
}

/// Thrown when the device has no connectivity (pre-flight check fails, or the
/// request dies with a transport error). Rows in this state must stay
/// `pending` — never `failed` — so the connectivity watcher retries them.
class OfflineException implements Exception {
  OfflineException(this.uri);

  final Uri uri;

  @override
  String toString() => 'device offline (cannot reach $uri)';
}

/// Thrown when the backend rejects the bearer token (HTTP 401) and a silent
/// re-auth didn't recover it. Rows in this state must stay `pending`: the
/// capture was produced successfully on-device and only the session lapsed,
/// so burning it to `failed` would discard real work.
class UnauthorizedException implements Exception {
  UnauthorizedException(this.uri);

  final Uri uri;

  @override
  String toString() => 'session expired or token rejected (401 at $uri)';
}

/// Refresh hook used to recover from an expired JWT. Returns the fresh token,
/// or null when re-auth isn't possible. Injected so [V2Sync] stays free of
/// auth dependencies.
typedef TokenRefresher = Future<String?> Function();

/// Sync client for the app's structured results -> backend /api/v2/*.
///
/// Only structured JSON is ever POSTed (never raw documents). Every payload
/// is tagged `source: "app"`. Offline results stay in the local store with
/// `pending`/`failed` status and are retried when connectivity resumes.
///
/// All result traffic is v2-only. The single v1 call in the app is the
/// `google-login` exchange in auth.dart — nothing here touches v1.
class V2Sync {
  // ignore_for_file: prefer_initializing_formals
  V2Sync({
    required String baseUrl,
    ResultStore? store,
    http.Client? client,
    this.token,
    TokenRefresher? onUnauthorized,
  }) : baseUrl = baseUrl,
       _store = store,
       _client = client ?? http.Client(),
       _onUnauthorized = onUnauthorized;

  final String baseUrl;
  final ResultStore? _store;
  final http.Client _client;
  final TokenRefresher? _onUnauthorized;
  String? token;

  String get _v2 => baseUrl.replaceAll(RegExp(r'/+$'), '');

  /// Deadline for one sync POST. A reachable-but-unresponsive backend must not
  /// stall a retry sweep forever.
  static const _requestTimeout = Duration(seconds: 30);

  static final Connectivity _connectivity = Connectivity();

  Future<ResultStore> _results() async =>
      _store ?? await ResultStore.instance();

  Map<String, String>? _authHeaders(String? token) => {
    'Content-Type': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  /// One POST attempt. Transport failures are normalized to
  /// [OfflineException] so callers can keep rows pending rather than failed.
  Future<http.Response> _post(
    Uri uri,
    String? token,
    Map<String, dynamic> payload,
  ) async {
    try {
      return await _client
          .post(uri, headers: _authHeaders(token), body: jsonEncode(payload))
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw OfflineException(uri);
    } on http.ClientException catch (_) {
      throw OfflineException(uri);
    } on SocketException catch (_) {
      throw OfflineException(uri);
    }
  }

  /// Best-effort silent re-auth. Returns the new token, or null on failure.
  /// Never throws.
  Future<String?> _tryRefresh() async {
    final refresh = _onUnauthorized;
    if (refresh == null) return null;
    try {
      return await refresh();
    } catch (_) {
      return null;
    }
  }

  /// POST one structured envelope to the matching v2 endpoint.
  /// Returns the server-side id when the backend creates one.
  Future<int?> postResult({
    required String kind,
    required Map<String, dynamic> envelope,
    String? token,
  }) async {
    final effectiveToken = token ?? this.token;
    final payload = {...envelope, 'source': 'app'};
    // Structured app results ride the v2 router family; endpoint mapping is
    // centralized here (POST /api/v2/lab-reports/upload-structured).
    final uri = Uri.parse('$_v2/api/v2/lab-reports/upload-structured');
    // Offline capture: keep the result queued locally instead of pretending
    // the sync failed. The connectivity watcher retries it on reconnect.
    if (!await isOnline()) {
      throw OfflineException(uri);
    }
    var resp = await _post(uri, effectiveToken, payload);
    if (resp.statusCode == 401) {
      // The JWT lapsed (backend expiry is 30 min). Try exactly one silent
      // re-auth, then replay the request with the new token. No loops: a
      // second 401 means the session is genuinely gone.
      final freshToken = await _tryRefresh();
      if (freshToken == null || freshToken.isEmpty) {
        throw UnauthorizedException(uri);
      }
      // `token` is shadowed by this method's parameter, so the field needs an
      // explicit `this.` to persist across subsequent rows.
      this.token = freshToken;
      resp = await _post(uri, freshToken, payload);
      if (resp.statusCode == 401) {
        throw UnauthorizedException(uri);
      }
    }
    if (resp.statusCode == 404) {
      // Backend route not deployed where the app points: keep the row
      // pending instead of marking it failed.
      throw RouteMissingException(uri);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError('sync failed: ${resp.statusCode} ${resp.body}');
    }
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['id'] is int) return decoded['id'] as int;
    } catch (_) {
      // Non-JSON success body — treat as synced without server id.
    }
    return null;
  }

  /// Retry every locally queued row. Rows that still fail stay `failed`
  /// with the latest error; rows that sync become `synced`.
  Future<SyncReport> retryQueued({String? token}) async {
    final effectiveToken = token ?? this.token;
    final store = await _results();
    final rows = await store.pending();
    var synced = 0;
    var failed = 0;
    var skippedOffline = 0;
    if (!await isOnline()) {
      return SyncReport(synced: 0, failed: 0, skippedOffline: rows.length);
    }
    for (final row in rows) {
      final id = row['id'] as int;
      try {
        final envelope =
            jsonDecode(row['result_json'] as String) as Map<String, dynamic>;
        final serverId = await postResult(
          kind: row['kind'] as String? ?? 'lab_report',
          envelope: envelope,
          token: effectiveToken,
        );
        await store.markSynced(id, serverId: serverId);
        synced++;
      } on RouteMissingException catch (e) {
        // Route isn't deployed here — leave the row pending for a later
        // retry instead of burning it to `failed`.
        debugPrint('V2Sync: $e — leaving row $id pending');
        skippedOffline++;
      } on OfflineException catch (e) {
        // Connectivity dropped mid-run — keep the row pending so the next
        // reconnect retries it.
        debugPrint('V2Sync: $e — leaving row $id pending');
        await store.markPending(id);
        skippedOffline++;
      } on UnauthorizedException catch (e) {
        // Session lapsed and silent re-auth failed. The on-device result is
        // still valid, so keep it pending for after the user signs in again.
        debugPrint('V2Sync: $e — leaving row $id pending');
        await store.markPending(id);
        skippedOffline++;
      } catch (e) {
        await store.markFailed(id, '$e');
        failed++;
      }
    }
    return SyncReport(
      synced: synced,
      failed: failed,
      skippedOffline: skippedOffline,
    );
  }

  static Future<bool> isOnline() async {
    try {
      final status = await _connectivity.checkConnectivity();
      return !status.contains(ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  /// Connectivity listener entry point: call once from app startup.
  static StreamSubscription<List<ConnectivityResult>> watchConnectivity(
    Future<void> Function() onReconnect,
  ) {
    // Fire only on an offline -> online transition, and never overlap sweeps:
    // connectivity flaps (Wi-Fi/cellular hand-off) would otherwise trigger
    // several retry runs at once and re-POST the same queued rows.
    var wasOnline = true;
    var running = false;
    return _connectivity.onConnectivityChanged.listen((status) async {
      final online = !status.contains(ConnectivityResult.none);
      final reconnected = online && !wasOnline;
      wasOnline = online;
      if (!reconnected || running) return;
      running = true;
      try {
        await onReconnect();
      } finally {
        running = false;
      }
    });
  }
}

@immutable
class SyncReport {
  const SyncReport({
    required this.synced,
    required this.failed,
    required this.skippedOffline,
  });
  final int synced;
  final int failed;
  final int skippedOffline;

  @override
  String toString() =>
      'SyncReport(synced=$synced, failed=$failed, skippedOffline=$skippedOffline)';
}
