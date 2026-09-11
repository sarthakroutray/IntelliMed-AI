import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local store for inference results before/after sync.
///
/// One row per captured document: the structured on-device result plus a
/// `sync_status` of `pending` | `synced` | `failed`. Raw images are kept as
/// file paths, never as blobs, to keep the DB small.
class ResultStore {
  ResultStore._(this._db);
  final Database _db;

  static ResultStore? _instance;

  static Future<ResultStore> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final dbPath = p.join(await getDatabasesPath(), 'intellimed_results.db');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE results(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            local_path TEXT NOT NULL,
            result_json TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            server_id INTEGER,
            error TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_results_sync ON results(sync_status, created_at)',
        );
      },
    );
    _instance = ResultStore._(db);
    return _instance!;
  }

  /// Visible for tests: open an isolated store at [path].
  static Future<ResultStore> openAt(String path) async {
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE results(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            local_path TEXT NOT NULL,
            result_json TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            server_id INTEGER,
            error TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
          )
        ''');
      },
    );
    return ResultStore._(db);
  }

  Future<int> insertPending({
    required String kind,
    required String localPath,
    required String resultJson,
  }) async {
    return _db.insert('results', {
      'kind': kind,
      'local_path': localPath,
      'result_json': resultJson,
      'sync_status': 'pending',
    });
  }

  Future<List<Map<String, Object?>>> pending() {
    return _db.query(
      'results',
      where: 'sync_status IN (?, ?)',
      whereArgs: ['pending', 'failed'],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, Object?>>> all({int limit = 100}) {
    return _db.query('results', orderBy: 'created_at DESC', limit: limit);
  }

  Future<int> markSynced(int id, {int? serverId}) async {
    return _db.update(
      'results',
      {
        'sync_status': 'synced',
        'server_id': serverId,
        'error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> markFailed(int id, String error) async {
    return _db.update(
      'results',
      {
        'sync_status': 'failed',
        'error': error,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> markPending(int id) async {
    return _db.update(
      'results',
      {
        'sync_status': 'pending',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() => _db.close();
}
