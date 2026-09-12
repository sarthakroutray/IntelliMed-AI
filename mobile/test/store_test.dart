import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The local result store drives the pending/synced/failed contract that keeps
/// offline captures from being lost, so its queries are worth covering.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late ResultStore store;

  setUp(() async {
    store = await ResultStore.openAt(inMemoryDatabasePath);
  });

  tearDown(() => store.close());

  Future<int> insert(String kind, {String status = 'pending'}) async {
    final id = await store.insertPending(
      kind: kind,
      localPath: '/tmp/$kind.jpg',
      resultJson: '{"kind":"$kind","normalized":{}}',
    );
    if (status == 'synced') await store.markSynced(id, serverId: 99);
    if (status == 'failed') await store.markFailed(id, 'boom');
    return id;
  }

  test('a new capture starts pending', () async {
    final id = await insert('lab_report');
    final row = await store.byId(id);
    expect(row, isNotNull);
    expect(row!['sync_status'], 'pending');
  });

  test('byId returns null for a missing row', () async {
    expect(await store.byId(12345), isNull);
  });

  test('counts reports each status and a total', () async {
    await insert('lab_report');
    await insert('xray', status: 'synced');
    await insert('prescription', status: 'failed');

    final counts = await store.counts();
    expect(counts['pending'], 1);
    expect(counts['synced'], 1);
    expect(counts['failed'], 1);
    expect(counts['total'], 3);
  });

  test('counts is all zeros on an empty store', () async {
    final counts = await store.counts();
    expect(counts['total'], 0);
    expect(counts['pending'], 0);
  });

  test('pending() includes failed rows so they are retried', () async {
    await insert('lab_report');
    await insert('xray', status: 'failed');
    await insert('prescription', status: 'synced');

    final rows = await store.pending();
    expect(rows, hasLength(2));
    expect(
      rows.map((r) => r['sync_status']).toSet(),
      {'pending', 'failed'},
    );
  });

  test('markSynced records the server id and clears any error', () async {
    final id = await insert('lab_report', status: 'failed');
    await store.markSynced(id, serverId: 42);

    final row = await store.byId(id);
    expect(row!['sync_status'], 'synced');
    expect(row['server_id'], 42);
    expect(row['error'], isNull);
  });

  test('byServerId finds every row synced to that id, whatever its kind', () async {
    // Lab reports and medical documents have separate id sequences server-side,
    // so the same id can legitimately match one row of each kind.
    final report = await insert('lab_report', status: 'synced');
    final xray = await insert('xray');
    await store.markSynced(xray, serverId: 99);

    final rows = await store.byServerId(99);
    expect(rows.map((r) => r['kind']).toSet(), {'lab_report', 'xray'});
    expect(rows.map((r) => r['id']).toSet(), {report, xray});
  });

  test('byServerId returns nothing for an unsynced or unknown id', () async {
    await insert('lab_report');
    expect(await store.byServerId(12345), isEmpty);
  });

  test('markPending keeps a row retryable after a transient failure', () async {
    final id = await insert('xray', status: 'failed');
    await store.markPending(id);

    final row = await store.byId(id);
    expect(row!['sync_status'], 'pending');
  });

  test('delete removes the row', () async {
    final id = await insert('lab_report');
    final removed = await store.delete(id);

    expect(removed, 1);
    expect(await store.byId(id), isNull);
    expect((await store.counts())['total'], 0);
  });

  test('all() returns newest first', () async {
    final first = await insert('lab_report');
    final second = await insert('xray');

    final rows = await store.all();
    expect(rows.first['id'], second);
    expect(rows.last['id'], first);
  });

  test('stored result_json round-trips verbatim', () async {
    final id = await store.insertPending(
      kind: 'lab_report',
      localPath: '/tmp/a.jpg',
      resultJson: '{"kind":"lab_report","normalized":{"panels":[]}}',
    );
    final row = await store.byId(id);
    expect(row!['result_json'], contains('"panels":[]'));
  });
}
