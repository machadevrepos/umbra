import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session_record.dart';
import '../models/hydration_mode.dart';
import '../ble/band_protocol.dart';
import '../ble/band_database.dart';

/// Shared session history: Home reads the most recent entry for its "Last
/// night" card, Active Session writes a new entry when a session ends, and
/// History/Insights (once built) read the full list. One store instead of
/// each screen re-deriving its own copy of "what happened."
///
/// History and ratings are stored locally and originate from a connected band.
class SessionStore extends ChangeNotifier {
  SessionStore() {
    ready = _load();
  }

  late final Future<void> ready;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  String? storageError;
  static const _key = 'session_history_v1';
  final BandDatabase bandDatabase = BandDatabase();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in prefs.getStringList(_key) ?? <String>[]) {
        try {
          final record = SessionRecord.fromJson(
            jsonDecode(entry) as Map<String, dynamic>,
          );
          if (record.deviceId != null &&
              !_history.any((s) => s.id == record.id)) {
            _history.add(record);
          }
        } catch (_) {
          storageError = 'Some saved nights could not be loaded.';
        }
      }
      await bandDatabase.migrateLegacyLogs();
      _history.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    } catch (_) {
      storageError = 'Saved nights could not be loaded.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _save() {
    final snapshot = _history.map((s) => jsonEncode(s.toJson())).toList();
    _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setStringList(_key, snapshot)) {
          throw StateError('Storage unavailable');
        }
        storageError = null;
      } catch (_) {
        storageError =
            'This change could not be saved. Keep the app open and try again.';
        if (!_disposed) notifyListeners();
      }
    });
    return _writes;
  }

  Future<int> logCursor(String deviceId) async {
    await ready;
    return bandDatabase.cursor(deviceId);
  }

  Future<void> importBandLog(
    String deviceId,
    List<BandLogRecord> batch,
    int next, {
    required bool currentlyNight,
  }) async {
    await ready;
    await bandDatabase.saveLog(deviceId, batch, next);
    final ordered = await bandDatabase.logs(deviceId);
    final group = <BandLogRecord>[];
    void finish() {
      if (group.isEmpty) return;
      final start = group.first.startedAt;
      final end = group.last.endedAt;
      final withHr = group
          .where((r) => r.hrAvg > 0 && r.durationSeconds > 0)
          .toList();
      final oxygen = group.where((r) => r.spo2 > 0).toList();
      final matching = _history
          .where(
            (r) =>
                r.deviceId == deviceId &&
                !r.endedAt.isBefore(start) &&
                !r.startedAt.isAfter(end),
          )
          .toList();
      final rated = matching.where((r) => r.checkInRating != null).toList();
      _history.removeWhere((r) => matching.contains(r));
      _history.add(
        SessionRecord(
          id: 'band:$deviceId:${group.first.boot}:${group.first.seq}',
          deviceId: deviceId,
          mode: HydrationMode.night,
          startedAt: start,
          endedAt: end,
          avgHr: withHr.isEmpty
              ? null
              : (withHr.fold<int>(
                          0,
                          (sum, r) => sum + r.hrAvg * r.durationSeconds,
                        ) /
                        withHr.fold<int>(
                          0,
                          (sum, r) => sum + r.durationSeconds,
                        ))
                    .round(),
          avgHrv: null,
          avgSpo2: oxygen.isEmpty
              ? null
              : (oxygen.fold<int>(0, (sum, r) => sum + r.spo2) / oxygen.length)
                    .round(),
          motion: 'Not provided by band',
          reminderCount: null,
          steps: group.every((r) => r.stepsValid)
              ? group.fold<int>(0, (sum, r) => sum + r.steps)
              : null,
          checkInRating: rated.isEmpty ? null : rated.first.checkInRating,
        ),
      );
      group.clear();
    }

    BandLogRecord? previous;
    for (final record in ordered) {
      if (previous != null &&
          (record.boot != previous.boot || record.seq != previous.seq + 1)) {
        finish();
      }
      if (record.timeIsUtc && record.night && record.durationSeconds > 0) {
        group.add(record);
      } else {
        finish();
      }
      previous = record;
    }
    if (!currentlyNight) finish();
    _history.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (!_disposed) notifyListeners();
    await _save();
  }

  Future<void> flush() => _writes;

  final List<SessionRecord> _history = [];

  /// Newest first.
  List<SessionRecord> get history => List.unmodifiable(_history);

  SessionRecord? get mostRecent => _history.isEmpty ? null : _history.first;

  Future<void> addSession(SessionRecord record) async {
    await ready;
    _history.removeWhere((s) => s.id == record.id);
    _history.insert(0, record);
    notifyListeners();
    await _save();
  }

  Future<void> attachCheckIn(String sessionId, int rating) async {
    if (rating < 1 || rating > 10) throw RangeError.range(rating, 1, 10);
    await ready;
    final index = _history.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;
    _history[index] = _history[index].copyWith(checkInRating: rating);
    notifyListeners();
    await _save();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
