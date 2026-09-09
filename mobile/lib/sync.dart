import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'store.dart';

/// Sync client for the app's structured results -> backend /api/v2/*.
///
/// Only structured JSON is ever POSTed (never raw documents). Every payload
/// is tagged `source: "app"`. Offline results stay in the local store with
/// `pending`/`failed` status and are retried when connectivity resumes.
///
/// v1 is never touched from this codebase — base URL + paths below are v2-only.
class V2Sync {
  // ignore_for_file: prefer_initializing_formals
  V2Sync({required String baseUrl, ResultStore? store, http.Client? client})
    : baseUrl = baseUrl,
      _store = store,
      _client = client ?? http.Client();

  final String baseUrl;
  final ResultStore? _store;
  final http.Client _client;

  String get _v2 => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<ResultStore> _results() async =>
      _store ?? await ResultStore.instance();

  Map<String, String>? _authHeaders(String? token) => {
    'Content-Type': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  /// POST one structured envelope to the matching v2 endpoint.
  /// Returns the server-side id when the backend creates one.
  Future<int?> postResult({
    required String kind,
    required Map<String, dynamic> envelope,
    String? token,
  }) async {
    final payload = {...envelope, 'source': 'app'};
    // Structured app results ride the v2 router family; endpoint mapping is
    // centralized here (POST /api/v2/lab-reports/upload-structured).
    final uri = Uri.parse('$_v2/api/v2/lab-reports/upload-structured');
    final resp = await _client.post(
      uri,
      headers: _authHeaders(token),
      body: jsonEncode(payload),
    );
    if (resp.statusCode == 404) {
      // Backend route not deployed where the app points: keep the row
      // pending instead of marking it failed.
      throw StateError('structured ingest route missing (404 at $uri)');
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
          token: token,
        );
        await store.markSynced(id, serverId: serverId);
        synced++;
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
      final status = await Connectivity().checkConnectivity();
      return !status.contains(ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  /// Connectivity listener entry point: call once from app startup.
  static StreamSubscription<List<ConnectivityResult>> watchConnectivity(
    Future<void> Function() onReconnect,
  ) {
    return Connectivity().onConnectivityChanged.listen((status) async {
      if (!status.contains(ConnectivityResult.none)) {
        await onReconnect();
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
