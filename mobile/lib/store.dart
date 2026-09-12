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
      // `created_at` is only second-resolution, so tie-break on id to keep the
      // retry order stable.
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<List<Map<String, Object?>>> all({int limit = 100}) {
    return _db.query(
      'results',
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
  }

  /// Lab-report rows for the trends view, oldest first.
  ///
  /// Trends read the stored envelope (the source of truth) rather than a
  /// denormalised table: at this data volume a query is cheaper than a
  /// migration plus the delete/re-run invalidation that a second table would
  /// need to stay correct.
  Future<List<Map<String, Object?>>> labReportRows({int limit = 500}) {
    return _db.query(
      'results',
      where: 'kind = ?',
      whereArgs: ['lab_report'],
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
  }

  /// A single stored row, for the capture detail viewer.
  Future<Map<String, Object?>?> byId(int id) async {
    final rows = await _db.query(
      'results',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Newest first for one source image. Used when re-running inference on a
  /// capture with a corrected document type, to find the row just created.
  Future<List<Map<String, Object?>>> byPath(String localPath) {
    return _db.query(
      'results',
      where: 'local_path = ?',
      whereArgs: [localPath],
      orderBy: 'id DESC',
    );
  }

  /// Local rows already synced to the server record [serverId].
  ///
  /// The server keeps lab reports and medical documents in separate tables with
  /// independent ids, so a single [serverId] can match two rows of different
  /// `kind`. Callers pick the row they mean by `kind`.
  Future<List<Map<String, Object?>>> byServerId(int serverId) {
    return _db.query(
      'results',
      where: 'server_id = ?',
      whereArgs: [serverId],
      orderBy: 'id DESC',
    );
  }

  /// Counts per sync status, for the Home dashboard. Computed in SQL so the
  /// dashboard doesn't load every row.
  Future<Map<String, int>> counts() async {
    final rows = await _db.rawQuery(
      'SELECT sync_status, COUNT(*) AS n FROM results GROUP BY sync_status',
    );
    final result = <String, int>{'pending': 0, 'synced': 0, 'failed': 0};
    var total = 0;
    for (final row in rows) {
      final status = '${row['sync_status']}';
      final n = (row['n'] as num?)?.toInt() ?? 0;
      result[status] = (result[status] ?? 0) + n;
      total += n;
    }
    result['total'] = total;
    return result;
  }

  /// Remove a locally stored capture (local only; never touches the server).
  Future<int> delete(int id) {
    return _db.delete('results', where: 'id = ?', whereArgs: [id]);
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
