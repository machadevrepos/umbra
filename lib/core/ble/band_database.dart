import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'band_protocol.dart';

class BandStepSnapshot {
  const BandStepSnapshot(this.steps, this.receivedAt);
  final int steps;
  final DateTime receivedAt;
}

/// Hardware logs and live counters have different units: period deltas versus
/// a counter since boot. Keep them separate so reconnects cannot double count.
class BandDatabase {
  static Future<Database>? _opening;
  static Database? _connection;

  Future<Database> get _database async {
    if (_connection != null) return _connection!;
    return _opening ??= _open();
  }

  Future<void> initialize() async {
    await _database;
  }

  static Future<Database> _open() async {
    try {
      final db = await openDatabase(
        path.join(await getDatabasesPath(), 'umbra_band.db'),
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE band_logs (
            device TEXT NOT NULL, seq INTEGER NOT NULL, payload TEXT NOT NULL,
            PRIMARY KEY (device, seq))''');
          await db.execute('''CREATE TABLE band_cursors (
            device TEXT PRIMARY KEY, next_seq INTEGER NOT NULL)''');
          await db.execute('''CREATE TABLE step_snapshots (
            device TEXT PRIMARY KEY, steps INTEGER NOT NULL,
            received_at INTEGER NOT NULL)''');
        },
      );
      _connection = db;
      return db;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<void> migrateLegacyLogs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
      (k) => k.startsWith('band_log_v2_'),
    )) {
      final saved = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      final device = key.substring('band_log_v2_'.length);
      if (await cursor(device) == 0) {
        await saveLog(
          device,
          (saved['records'] as List? ?? [])
              .map((v) => BandLogRecord.fromJson(v as List))
              .toList(),
          saved['next'] as int? ?? 0,
        );
      }
      // Remove only after SQLite has committed the records and cursor.
      if (!await prefs.remove(key)) {
        throw StateError('Could not migrate band log');
      }
    }
  }

  Future<int> cursor(String device) async {
    final rows = await (await _database).query(
      'band_cursors',
      where: 'device = ?',
      whereArgs: [device],
    );
    return rows.isEmpty ? 0 : rows.single['next_seq'] as int;
  }

  Future<List<BandLogRecord>> logs(String device) async {
    final rows = await (await _database).query(
      'band_logs',
      where: 'device = ?',
      whereArgs: [device],
      orderBy: 'seq',
    );
    return rows
        .map(
          (r) => BandLogRecord.fromJson(
            jsonDecode(r['payload'] as String) as List,
          ),
        )
        .toList();
  }

  Future<void> saveLog(
    String device,
    List<BandLogRecord> records,
    int next,
  ) async {
    await (await _database).transaction((txn) async {
      final batch = txn.batch();
      for (final record in records) {
        batch.insert('band_logs', {
          'device': device,
          'seq': record.seq,
          'payload': jsonEncode(record.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      batch.insert('band_cursors', {
        'device': device,
        'next_seq': next,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await batch.commit(noResult: true);
    });
  }

  Future<void> saveSteps(String device, int steps, DateTime at) async {
    await (await _database).insert('step_snapshots', {
      'device': device,
      'steps': steps,
      'received_at': at.toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<BandStepSnapshot?> lastSteps(String device) async {
    final rows = await (await _database).query(
      'step_snapshots',
      where: 'device = ?',
      whereArgs: [device],
    );
    if (rows.isEmpty) return null;
    return BandStepSnapshot(
      rows.single['steps'] as int,
      DateTime.fromMillisecondsSinceEpoch(
        rows.single['received_at'] as int,
        isUtc: true,
      ).toLocal(),
    );
  }

  static Future<void> close() async {
    final opening = _opening;
    _opening = null;
    _connection = null;
    if (opening != null) await (await opening).close();
  }
}
