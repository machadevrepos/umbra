import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/hydration_mode.dart';
import '../models/session_record.dart';
import 'band_controller.dart';
import 'session_store.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required BandController band,
    required SessionStore history,
  }) : _band = band,
       _history = history {
    _band.addListener(_onBandChanged);
    ready = _restore();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isActive) notifyListeners();
    });
  }
  final BandController _band;
  final SessionStore _history;
  late final Future<void> ready;
  Timer? _ticker;
  DateTime? _startedAt;
  String? _sessionDevice;
  bool _disposed = false;
  bool _interrupted = false;
  int _lastHrSequence = -1,
      _hrSum = 0,
      _hrCount = 0,
      _oxygenSum = 0,
      _oxygenCount = 0;
  DateTime? _lastOxygenAt;
  int? _stepBaseline;
  int? _lastStepCount;
  bool _stepCounterReset = false;
  int? get steps =>
      _stepBaseline == null ||
          _band.steps == null ||
          _band.steps! < _stepBaseline! ||
          _interrupted ||
          _stepCounterReset
      ? null
      : _band.steps! - _stepBaseline!;
  Future<void> _writes = Future.value();
  Future<void> _finished = Future.value();
  bool get isActive => _startedAt != null;
  bool get hardwareConfirmed =>
      _band.connected &&
      _band.configurationReady &&
      _band.mode == HydrationMode.night;
  DateTime? get startedAt => _startedAt;
  int get elapsedSeconds => _startedAt == null
      ? 0
      : DateTime.now().difference(_startedAt!).inSeconds.clamp(0, 1 << 31);
  int? get intervalMinutes => _band.nightIntervalMinutes;
  int? get hr => hardwareConfirmed ? _band.heartRate : null;
  int? get avgHr => _hrCount == 0 ? null : (_hrSum / _hrCount).round();
  int? get avgSpo2 =>
      _oxygenCount == 0 ? null : (_oxygenSum / _oxygenCount).round();
  int? get spo2 =>
      hardwareConfirmed &&
          (_band.spo2Reading?.isRecent(DateTime.now()) ?? false)
      ? _band.spo2Reading?.percent
      : null;

  Future<void> _restore() async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(
        'active_hardware_session_v1',
      );
      if (value != null && !isActive && !_disposed) {
        final data = jsonDecode(value) as Map<String, dynamic>;
        _sessionDevice = data['device'] as String;
        _startedAt = DateTime.parse(data['start'] as String).toLocal();
        _hrSum = data['hrSum'] as int;
        _hrCount = data['hrCount'] as int;
        _oxygenSum = data['oxygenSum'] as int;
        _oxygenCount = data['oxygenCount'] as int;
        _stepBaseline = data['stepBaseline'] as int?;
        _interrupted = true;
        _onBandChanged();
      }
    } catch (_) {}
  }

  Future<void> _persist() {
    final data = isActive
        ? jsonEncode({
            'device': _sessionDevice,
            'start': _startedAt!.toUtc().toIso8601String(),
            'hrSum': _hrSum,
            'hrCount': _hrCount,
            'oxygenSum': _oxygenSum,
            'oxygenCount': _oxygenCount,
            'stepBaseline': _stepBaseline,
          })
        : null;
    _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (data == null) {
          await prefs.remove('active_hardware_session_v1');
        } else {
          await prefs.setString('active_hardware_session_v1', data);
        }
      } catch (_) {}
    });
    return _writes;
  }

  Future<void> startSession() => _band.setMode(HydrationMode.night);
  Future<void> endSession() async {
    await _band.setMode(HydrationMode.daily);
    await _finished;
  }

  void _begin() {
    _startedAt = DateTime.now();
    _sessionDevice = _band.deviceId;
    _interrupted = false;
    _hrSum = 0;
    _hrCount = 0;
    _oxygenSum = 0;
    _oxygenCount = 0;
    _lastHrSequence = _band.heartRateSequence;
    _lastOxygenAt = null;
    _stepBaseline = _band.stepsAt == null ? null : _band.steps;
    _lastStepCount = _stepBaseline;
    _stepCounterReset = false;
    unawaited(_persist());
  }

  void _onBandChanged() {
    if (_disposed) return;
    if (!_band.connected) {
      if (isActive) _interrupted = true;
      notifyListeners();
      return;
    }
    if (!_band.configurationReady || _band.mode == null) return;
    if (isActive && _band.steps != null) {
      if (_lastStepCount != null && _band.steps! < _lastStepCount!) {
        _stepCounterReset = true;
      }
      _lastStepCount = _band.steps;
    }
    if (_band.mode == HydrationMode.night) {
      if (!isActive || _sessionDevice != _band.deviceId) _begin();
      if (_lastHrSequence != _band.heartRateSequence) {
        _lastHrSequence = _band.heartRateSequence;
        final value = _band.heartRate;
        if (value != null) {
          _hrSum += value;
          _hrCount++;
          unawaited(_persist());
        }
      }
      final oxygen = _band.spo2Reading;
      if (oxygen?.status == 1 &&
          oxygen?.measuredAt != null &&
          oxygen!.measuredAt != _lastOxygenAt &&
          !oxygen.measuredAt!.isBefore(_startedAt!) &&
          oxygen.isRecent(DateTime.now())) {
        _lastOxygenAt = oxygen.measuredAt;
        _oxygenSum += oxygen.percent!;
        _oxygenCount++;
        unawaited(_persist());
      }
    } else if (isActive) {
      if (!_interrupted && _sessionDevice == _band.deviceId) {
        final record = SessionRecord(
          id: 'live:${_sessionDevice!}:${_startedAt!.microsecondsSinceEpoch}',
          deviceId: _sessionDevice,
          mode: HydrationMode.night,
          startedAt: _startedAt!,
          endedAt: DateTime.now(),
          avgHr: avgHr,
          avgHrv: null,
          avgSpo2: avgSpo2,
          motion: 'Not provided by band',
          reminderCount: null,
          steps: steps,
        );
        _finished = _history.addSession(record);
      }
      // After a disconnect only the firmware log can tell us when a night ended.
      _startedAt = null;
      _sessionDevice = null;
      unawaited(_persist());
    }
    notifyListeners();
  }

  Future<void> flush() async {
    await _writes;
    await _finished;
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _band.removeListener(_onBandChanged);
    super.dispose();
  }
}
