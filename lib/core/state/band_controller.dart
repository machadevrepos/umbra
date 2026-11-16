import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ble/band_ble_constants.dart';
import '../ble/band_storage.dart';
import '../ble/band_protocol.dart';
import '../ble/band_gatt.dart';
import '../models/hydration_mode.dart';
import 'session_store.dart';
import 'dart:convert';
import '../permissions/band_permissions.dart';

/// Where the band link currently stands. The pairing screen and the band
/// status card both read this instead of re-deriving it from lower-level
/// state, so there's exactly one place that decides what "connecting" or
/// "reconnecting" means.
enum BandLinkState {
  /// Not connected and not trying: either never paired, or the user
  /// explicitly forgot the band.
  idle,

  /// Bluetooth itself is off, unauthorized, or unsupported at the OS level.
  bluetoothUnavailable,

  /// Scan/connect permission was denied.
  permissionDenied,

  scanning,
  connecting,
  connected,

  /// Was connected, lost the link (band powered off, out of range, app
  /// backgrounded through a system-killed radio), and is retrying with
  /// backoff. The band itself keeps buzzing on schedule regardless, see
  /// side_notes.md: "reconnection handling should be graceful, never
  /// blocking core reminder behavior."
  reconnecting,
}

class BandScanMatch {
  const BandScanMatch({
    required this.id,
    required this.name,
    required this.rssi,
  });
  final String id;
  final String name;
  final int rssi;
}

/// Band connection state shared between Home's status pill, Band Detail,
/// and the pairing flow. Owns the real BLE link end to end: scanning,
/// connecting, reconnect-with-backoff on an unexpected drop, and
/// persisting the last-paired device so the app reconnects quietly on its
/// own next launch.
///
/// Every entry point into `flutter_reactive_ble`/`permission_handler` is
/// wrapped so a platform error (Bluetooth off, permission denied, no
/// plugin registered at all, e.g. in a widget test) changes [state]
/// instead of throwing, per the product requirement that losing the band
/// link, or Bluetooth itself, must never take the app down with it.
class BandController extends ChangeNotifier with WidgetsBindingObserver {
  BandController({
    required SessionStore history,
    bool initialize = true,
    BandGatt Function(String)? gattFactory,
  }) : _history = history,
       _gattFactory = gattFactory {
    WidgetsBinding.instance.addObserver(this);
    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_disposed && connected) notifyListeners();
    });
    if (initialize &&
        (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      _ble = FlutterReactiveBle();
      _bootstrap();
    }
  }

  FlutterReactiveBle? _ble;
  final BandPermissions _permissions = const BandPermissions();
  bool _disposed = false;
  int _connectionGeneration = 0;
  int readingSequence = 0;
  String? scanIssue;
  final SessionStore _history;
  final BandGatt Function(String)? _gattFactory;
  BandGatt? _gatt;
  final List<StreamSubscription<List<int>>> _measurements = [];
  Timer? _freshnessTimer;
  bool configurationReady = false;
  bool commandBusy = false;
  String? deviceError;
  HydrationMode? mode;
  int? dailyIntervalMinutes;
  int? nightIntervalMinutes;
  int? steps;
  DateTime? stepsAt;
  DateTime? batteryAt;
  String? readingIssue;
  int _batteryRevision = 0;
  int _modeRevision = 0;
  int _gattGeneration = 0;
  Future<void> _stepWrites = Future.value();
  Timer? _batteryRefreshTimer;
  String? firmwareVersion;
  BandSpo2Reading? spo2Reading;
  int? _heartRate;
  DateTime? heartRateAt;
  int heartRateSequence = 0;
  int spo2Sequence = 0;
  int? get heartRate =>
      connected &&
          heartRateAt != null &&
          DateTime.now().difference(heartRateAt!) < const Duration(seconds: 3)
      ? _heartRate
      : null;
  String? get deviceId => _deviceId;
  bool get canControl => connected && configurationReady && !commandBusy;
  int? get activeIntervalMinutes =>
      mode == HydrationMode.night ? nightIntervalMinutes : dailyIntervalMinutes;
  int _recordLength = 20;
  final List<BandLogRecord> _incomingLog = [];
  bool _logTransferValid = true;
  int _logRequestNext = 0;
  int _logRequestFirst = 0;
  Future<void> _logWrites = Future.value();

  BandLinkState _state = BandLinkState.idle;
  BleStatus _adapterStatus = BleStatus.unknown;
  String? _deviceId;
  String _deviceName = '';
  int _battery = -1;
  DateTime? _lastSeenAt;
  bool _userInitiatedDisconnect = false;
  int _reconnectAttempt = 0;
  final List<BandScanMatch> _scanResults = [];

  StreamSubscription<BleStatus>? _statusSub;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  Timer? _reconnectTimer;

  static const _reconnectBackoff = [2, 5, 10, 20, 30];

  BandLinkState get state => _state;
  bool get connected => _state == BandLinkState.connected;
  bool get bluetoothOn => _adapterStatus == BleStatus.ready;
  int get battery => _battery;
  int get restingHr => heartRate ?? 0;
  String get deviceName => _deviceName.isEmpty ? 'Umbra band' : _deviceName;
  List<BandScanMatch> get scanResults => List.unmodifiable(_scanResults);

  /// When a reading last actually arrived from the band, `null` if it
  /// never has this app lifetime. Distinguishes "no data yet" from "the
  /// numbers on screen are cached from before the link dropped."
  DateTime? get lastSeenAt => _lastSeenAt;

  /// [battery]/[restingHr] reflect a live reading right now vs. a cached
  /// value from before the link dropped. Screens use this to decide
  /// whether to show the numbers as current or mark them stale.
  bool get readingsAreStale =>
      _lastSeenAt != null &&
      (!connected ||
          DateTime.now().difference(_lastSeenAt!) >
              const Duration(seconds: 30));

  Future<void> _bootstrap() async {
    _statusSub = _ble!.statusStream.listen(_onAdapterStatus, onError: (_) {});
    try {
      final saved = await BandStorage.loadLastDevice();
      if (_disposed) return;
      if (saved != null) {
        _deviceId = saved.id;
        _deviceName = saved.name;
        unawaited(_restoreSteps(saved.id));
        if (bluetoothOn) unawaited(_connectToKnownDevice());
      }
    } catch (_) {
      // Preferences unavailable, e.g. a test harness with no plugin
      // registered: nothing to restore, the rest of the app still works.
    }
  }

  void _onAdapterStatus(BleStatus status) {
    if (_disposed) return;
    final wasReady = _adapterStatus == BleStatus.ready;
    _adapterStatus = status;

    if (status != BleStatus.ready) {
      _reconnectTimer?.cancel();
      unawaited(stopScan());
      if (_state == BandLinkState.connected ||
          _state == BandLinkState.reconnecting) {
        // The band itself doesn't care, it keeps firing reminders on its
        // own schedule. This only affects what the app can show.
        _state = BandLinkState.reconnecting;
      } else if (_state != BandLinkState.idle) {
        _state = BandLinkState.bluetoothUnavailable;
      }
      notifyListeners();
      return;
    }

    // Bluetooth just became ready (including the first-ever ready signal
    // at cold start): pick back up with the last-known device, if any.
    if (!wasReady && _deviceId != null && _state != BandLinkState.connected) {
      _reconnectAttempt = 0;
      _connectToKnownDevice();
    }
    notifyListeners();
  }

  Future<void> _connectToKnownDevice() async {
    final id = _deviceId;
    final name = _deviceName;
    if (id == null) return;
    _userInitiatedDisconnect = false;
    _state = BandLinkState.connecting;
    notifyListeners();
    await _connect(id, name);
  }

  Future<void> _connect(String id, String name) async {
    final generation = ++_connectionGeneration;
    await _connectionSub?.cancel();
    if (_disposed ||
        generation != _connectionGeneration ||
        _userInitiatedDisconnect) {
      return;
    }
    try {
      _connectionSub = _ble!
          .connectToDevice(
            id: id,
            connectionTimeout: BandBleConstants.connectionTimeout,
          )
          .listen(
            (update) {
              if (!_disposed && generation == _connectionGeneration) {
                _onConnectionUpdate(id, name, update);
              }
            },
            onError: (_) {
              if (!_disposed && generation == _connectionGeneration) {
                _onLinkDropped(id, name);
              }
            },
          );
    } catch (_) {
      _onLinkDropped(id, name);
    }
  }

  void _onConnectionUpdate(
    String id,
    String name,
    ConnectionStateUpdate update,
  ) {
    switch (update.connectionState) {
      case DeviceConnectionState.connecting:
        _state = BandLinkState.connecting;
        notifyListeners();
      case DeviceConnectionState.connected:
        if (_deviceId != id) _clearReadings();
        _deviceId = id;
        _deviceName = name;
        _reconnectAttempt = 0;
        _state = BandLinkState.connected;
        unawaited(BandStorage.saveLastDevice(id: id, name: name));
        unawaited(_initializeGatt(id));
        notifyListeners();
      case DeviceConnectionState.disconnecting:
        break;
      case DeviceConnectionState.disconnected:
        _onLinkDropped(id, name);
    }
  }

  void _onLinkDropped(String id, String name) {
    if (_disposed) return;
    configurationReady = false;
    _gattGeneration++;
    _batteryRefreshTimer?.cancel();
    _gatt = null;
    _heartRate = null;
    heartRateAt = null;
    for (final subscription in _measurements) {
      unawaited(subscription.cancel());
    }
    _measurements.clear();
    if (_userInitiatedDisconnect) {
      _state = BandLinkState.idle;
    } else {
      _state = BandLinkState.reconnecting;
      _scheduleReconnect(id, name);
    }
    notifyListeners();
  }

  void _scheduleReconnect(String id, String name) {
    _reconnectTimer?.cancel();
    final delay =
        _reconnectBackoff[_reconnectAttempt.clamp(
          0,
          _reconnectBackoff.length - 1,
        )];
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (_state == BandLinkState.reconnecting && bluetoothOn) {
        _connect(id, name);
      }
    });
  }

  Future<void> _initializeGatt(String id) async {
    final initialization = ++_gattGeneration;
    _batteryRefreshTimer?.cancel();
    final previous = List.of(_measurements);
    _measurements.clear();
    configurationReady = false;
    for (final subscription in previous) {
      await subscription.cancel();
    }
    if (_disposed || initialization != _gattGeneration || !connected) return;
    final generation = _connectionGeneration;
    configurationReady = false;
    deviceError = null;
    final gatt =
        _gattFactory?.call(id) ??
        ReactiveBandGatt(_ble!, id, servicesAlreadyDiscovered: Platform.isIOS);
    _gatt = gatt;
    bool current() =>
        !_disposed &&
        connected &&
        initialization == _gattGeneration &&
        generation == _connectionGeneration &&
        identical(gatt, _gatt);
    final revisions = <String, int>{};
    var notificationsFailed = false;
    void listen(
      String service,
      String characteristic,
      void Function(List<int>) apply,
    ) {
      _measurements.add(
        gatt
            .subscribe(service, characteristic)
            .listen(
              (value) {
                if (!current()) return;
                revisions[characteristic] =
                    (revisions[characteristic] ?? 0) + 1;
                try {
                  apply(value);
                } catch (_) {
                  readingIssue =
                      'The band sent an unreadable reading. Keeping the last valid value.';
                }
                if (current()) notifyListeners();
              },
              onError: (_) {
                if (!current()) return;
                notificationsFailed = true;
                configurationReady = false;
                deviceError = 'Band readings stopped. Reconnect the band.';
                notifyListeners();
              },
            ),
      );
    }

    Future<void> readCurrent(
      String service,
      String characteristic,
      void Function(List<int>) apply,
    ) async {
      if (!current()) throw StateError('Connection changed');
      final revision = revisions[characteristic] ?? 0;
      final value = await gatt.read(service, characteristic);
      if (!current()) throw StateError('Connection changed');
      // A notification received during the read is newer than its response.
      if (current() && revision == (revisions[characteristic] ?? 0)) {
        apply(value);
      }
    }

    var setupStage = 'discover band services';
    try {
      if (Platform.isAndroid && _ble != null) {
        try {
          await _ble!
              .requestMtu(deviceId: id, mtu: 247)
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
      await gatt.discover().timeout(const Duration(seconds: 10));
      if (!current()) return;
      setupStage = 'set the band clock';
      await gatt.write(
        BandProtocol.service,
        BandProtocol.characteristic(5),
        BandProtocol.time(DateTime.now()),
      );
      if (!current()) return;
      listen(BandProtocol.heartService, BandProtocol.heart, (value) {
        _heartRate = BandProtocol.heartRate(value);
        heartRateAt = _heartRate == null ? null : DateTime.now();
        _lastSeenAt = DateTime.now();
        heartRateSequence++;
      });
      listen(BandProtocol.batteryService, BandProtocol.battery, _applyBattery);
      listen(BandProtocol.service, BandProtocol.characteristic(1), _applySteps);
      listen(BandProtocol.service, BandProtocol.characteristic(2), (value) {
        mode = BandProtocol.mode(value);
        _modeRevision++;
      });
      listen(BandProtocol.service, BandProtocol.characteristic(9), _applySpo2);
      listen(
        BandProtocol.service,
        BandProtocol.characteristic(8),
        (value) => _onLogData(id, value),
      );
      setupStage = 'enable band readings';
      await gatt.notificationsReady();
      if (!current()) return;
      setupStage = 'read the band settings';
      await readCurrent(
        BandProtocol.service,
        BandProtocol.characteristic(2),
        (value) => mode = BandProtocol.mode(value),
      );
      await readCurrent(
        BandProtocol.service,
        BandProtocol.characteristic(4),
        _applyIntervals,
      );
      await gatt.read(BandProtocol.service, BandProtocol.characteristic(6));
      await readCurrent(
        BandProtocol.batteryService,
        BandProtocol.battery,
        _applyBattery,
      );
      setupStage = 'read band sensors';
      await readCurrent(
        BandProtocol.service,
        BandProtocol.characteristic(1),
        _applySteps,
      );
      await readCurrent(
        BandProtocol.service,
        BandProtocol.characteristic(9),
        _applySpo2,
      );
      await readCurrent(
        BandProtocol.infoService,
        BandProtocol.firmware,
        (value) =>
            firmwareVersion = utf8.decode(value, allowMalformed: true).trim(),
      );
      setupStage = 'read band history';
      final control = await gatt.read(
        BandProtocol.service,
        BandProtocol.characteristic(7),
      );
      if (!current()) return;
      if (control.length != 12 ||
          !((control[10] == 16 && control[11] == 1) ||
              (control[10] == 20 && control[11] == 2))) {
        throw const FormatException('Unsupported band history format');
      }
      _recordLength = control[10];
      _logRequestNext = BandProtocol.bytes(control).getUint32(4, Endian.little);
      final cursor = await _history.logCursor(id);
      final oldest = BandProtocol.bytes(control).getUint32(0, Endian.little);
      final from = cursor > _logRequestNext ? 0 : cursor;
      _logRequestFirst = from == 0 || from < oldest ? oldest : from;
      _incomingLog.clear();
      _logTransferValid = true;
      if (!current()) return;
      if (notificationsFailed) {
        setupStage = 'keep band readings active';
        throw StateError('Band notifications stopped');
      }
      configurationReady = true;
      _batteryRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (current()) unawaited(refreshBattery());
      });
      notifyListeners();
      await gatt.write(
        BandProtocol.service,
        BandProtocol.characteristic(7),
        BandProtocol.logRequest(cursor > _logRequestNext ? 0 : cursor),
      );
    } catch (error, stack) {
      if (current()) {
        configurationReady = false;
        deviceError =
            'Could not $setupStage. Reconnect your band and try again.';
        debugPrint('Band setup failed ($setupStage): $error\n$stack');
        notifyListeners();
      }
    }
  }

  void _applyBattery(List<int> value) {
    if (value.length != 1 || value.single < 0 || value.single > 100) {
      throw const FormatException('Invalid battery');
    }
    final revision = ++_batteryRevision;
    final now = DateTime.now();
    if (_battery >= 0 &&
        _battery - value.single > 20 &&
        batteryAt != null &&
        now.difference(batteryAt!) < const Duration(minutes: 1)) {
      readingIssue = 'Checking a sudden battery change with your band.';
      unawaited(_verifyBattery(revision));
      return;
    }
    _acceptBattery(value.single);
  }

  void _acceptBattery(int value) {
    _battery = value;
    batteryAt = DateTime.now();
    _lastSeenAt = batteryAt;
    readingIssue = null;
  }

  Future<void> _verifyBattery(int revision) async {
    final gatt = _gatt;
    final generation = _gattGeneration;
    if (gatt == null) return;
    bool current() =>
        !_disposed &&
        connected &&
        identical(gatt, _gatt) &&
        generation == _gattGeneration &&
        revision == _batteryRevision;
    try {
      final value = await gatt
          .read(BandProtocol.batteryService, BandProtocol.battery)
          .timeout(const Duration(seconds: 5));
      if (!current()) return;
      if (value.length != 1 || value.single < 0 || value.single > 100) {
        throw const FormatException('Invalid battery');
      }
      _acceptBattery(value.single);
    } catch (_) {
      if (!current()) return;
      readingIssue =
          'Battery change could not be verified. Showing the last confirmed reading.';
    }
    if (current()) notifyListeners();
  }

  Future<void> refreshBattery() async {
    await _verifyBattery(++_batteryRevision);
  }

  Future<void> _restoreSteps(String id) async {
    try {
      final saved = await _history.bandDatabase.lastSteps(id);
      if (!_disposed && id == _deviceId && stepsAt == null && saved != null) {
        steps = saved.steps;
        // Cached values stay explicitly unavailable to live session accounting.
        notifyListeners();
      }
    } catch (_) {
      if (!_disposed) readingIssue = 'Saved step count could not be loaded.';
    }
  }

  void _applySteps(List<int> value) {
    if (value.length != 4) throw const FormatException('Invalid steps');
    steps = BandProtocol.bytes(value).getUint32(0, Endian.little);
    stepsAt = DateTime.now();
    _lastSeenAt = stepsAt;
    final id = _deviceId;
    final count = steps!;
    final at = stepsAt!;
    if (id != null) {
      _stepWrites = _stepWrites.then((_) async {
        try {
          await _history.bandDatabase.saveSteps(id, count, at);
        } catch (_) {
          if (!_disposed) {
            readingIssue = 'Step count could not be saved. Reconnect to retry.';
            notifyListeners();
          }
        }
      });
    }
  }

  Future<void> flushReadings() async {
    await _stepWrites;
    await _logWrites;
  }

  void _applySpo2(List<int> value) {
    spo2Reading = BandSpo2Reading.decode(value);
    spo2Sequence++;
    _lastSeenAt = DateTime.now();
  }

  void _applyIntervals(List<int> value) {
    if (value.length != 4) throw const FormatException('Invalid intervals');
    final data = BandProtocol.bytes(value);
    final daily = data.getUint16(0, Endian.little);
    final night = data.getUint16(2, Endian.little);
    if (daily > 240 || night > 240) {
      throw const FormatException('Invalid intervals');
    }
    dailyIntervalMinutes = daily == 0 ? 90 : daily;
    nightIntervalMinutes = night == 0 ? 35 : night;
  }

  void _onLogData(String id, List<int> value) {
    if (value.length == 4) {
      final next = BandProtocol.bytes(value).getUint32(0, Endian.little);
      final unique = {
        for (final record in _incomingLog) record.seq: record,
      }.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));
      final complete = unique.isEmpty
          ? next == _logRequestFirst
          : unique.first.seq == _logRequestFirst &&
                unique.last.seq + 1 == next &&
                List.generate(
                  unique.length,
                  (i) => unique[i].seq == _logRequestFirst + i,
                ).every((v) => v);
      if (!_logTransferValid || next < _logRequestNext || !complete) {
        deviceError = 'Band history was incomplete. Reconnect to retry.';
        return;
      }
      final batch = List<BandLogRecord>.of(_incomingLog);
      _incomingLog.clear();
      final night = mode == HydrationMode.night;
      _logWrites = _logWrites.then((_) async {
        try {
          await _history.importBandLog(id, batch, next, currentlyNight: night);
        } catch (_) {
          if (!_disposed) {
            deviceError =
                'Band history could not be saved. Reconnect to retry.';
            notifyListeners();
          }
        }
      });
      return;
    }
    try {
      _incomingLog.addAll(BandLogRecord.decode(value, _recordLength));
    } catch (_) {
      _logTransferValid = false;
      deviceError = 'Band history was incomplete. Reconnect to retry.';
    }
  }

  Future<void> _command(Future<void> Function(BandGatt) action) async {
    if (!canControl || _gatt == null) {
      throw StateError('Connect your band before changing it.');
    }
    final gatt = _gatt!;
    commandBusy = true;
    deviceError = null;
    notifyListeners();
    try {
      await action(gatt).timeout(const Duration(seconds: 10));
      if (!connected || !identical(gatt, _gatt)) {
        throw StateError('Band disconnected');
      }
    } catch (_) {
      deviceError =
          'The band did not confirm the change. Reconnect and try again.';
      rethrow;
    } finally {
      commandBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> setMode(HydrationMode requested) => _command((gatt) async {
    if (mode == requested) return;
    await gatt.write(BandProtocol.service, BandProtocol.characteristic(2), [
      requested == HydrationMode.night ? 1 : 0,
    ]);
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (mode != requested && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final revision = _modeRevision;
      final value = await _readConnected(
        gatt,
        BandProtocol.service,
        BandProtocol.characteristic(2),
      );
      if (revision == _modeRevision) mode = BandProtocol.mode(value);
      if (!_disposed) notifyListeners();
    }
    if (mode != requested) throw StateError('Mode was not applied');
  });
  Future<void> setInterval(HydrationMode target, int minutes) =>
      _command((gatt) async {
        _applyIntervals(
          await _readConnected(
            gatt,
            BandProtocol.service,
            BandProtocol.characteristic(4),
          ),
        );
        final daily = target == HydrationMode.daily
            ? minutes
            : dailyIntervalMinutes!;
        final night = target == HydrationMode.night
            ? minutes
            : nightIntervalMinutes!;
        await gatt.write(
          BandProtocol.service,
          BandProtocol.characteristic(4),
          BandProtocol.intervals(daily, night),
        );
        _applyIntervals(
          await _readConnected(
            gatt,
            BandProtocol.service,
            BandProtocol.characteristic(4),
          ),
        );
        if (dailyIntervalMinutes != daily || nightIntervalMinutes != night) {
          throw StateError('Interval not applied');
        }
      });
  Future<List<int>> _readConnected(
    BandGatt gatt,
    String service,
    String characteristic,
  ) async {
    if (_disposed || !connected || !identical(gatt, _gatt)) {
      throw StateError('Band disconnected');
    }
    final value = await gatt.read(service, characteristic);
    if (_disposed || !connected || !identical(gatt, _gatt)) {
      throw StateError('Band disconnected');
    }
    return value;
  }

  Future<void> triggerHaptic() => _command(
    (gatt) =>
        gatt.write(BandProtocol.service, BandProtocol.characteristic(3), [1]),
  );
  Future<void> measureSpo2() => _command(
    (gatt) =>
        gatt.write(BandProtocol.service, BandProtocol.characteristic(9), [1]),
  );
  Future<void> syncTime() => _command(
    (gatt) => gatt.write(
      BandProtocol.service,
      BandProtocol.characteristic(5),
      BandProtocol.time(DateTime.now()),
    ),
  );

  Future<void> retryInitialization() async {
    if (!connected || _deviceId == null) throw StateError('Band disconnected');
    await _initializeGatt(_deviceId!);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && canControl) {
      unawaited(syncTime().catchError((Object _) {}));
    }
  }

  Future<void> startScan() async {
    if (_state == BandLinkState.scanning) return;
    scanIssue = null;

    final granted = (await _permissions.status(request: true)).isGranted;
    if (_disposed) return;
    if (!granted) {
      _state = BandLinkState.permissionDenied;
      notifyListeners();
      return;
    }
    if (!bluetoothOn) {
      _state = BandLinkState.bluetoothUnavailable;
      notifyListeners();
      return;
    }

    _scanResults.clear();
    _state = BandLinkState.scanning;
    notifyListeners();

    try {
      // Filters on advertised name, not service UUID: see the comment on
      // BandBleConstants.advertisedNamePrefixes. Location services aren't
      // required since the scan never derives location from results (the
      // manifest declares `neverForLocation` for the same reason).
      final requireLocationServices = await _permissions
          .locationServicesRequired();
      if (_disposed) return;
      if (requireLocationServices &&
          !(await Permission.locationWhenInUse.serviceStatus).isEnabled) {
        if (_disposed) return;
        scanIssue =
            'Turn on Location services to scan on this Android version.';
        _state = BandLinkState.idle;
        notifyListeners();
        return;
      }
      _scanSub = _ble!
          .scanForDevices(
            withServices: const [],
            requireLocationServicesEnabled: requireLocationServices,
          )
          .listen(
            _onScanResult,
            onError: (_) {
              if (_disposed) return;
              scanIssue = 'The scan stopped. Check Bluetooth and try again.';
              unawaited(stopScan());
            },
          );
    } catch (_) {
      _state = BandLinkState.idle;
      notifyListeners();
    }
  }

  void _onScanResult(DiscoveredDevice device) {
    final name = device.name;
    final matchesBand = BandBleConstants.advertisedNamePrefixes.any(
      (prefix) => name.toLowerCase().startsWith(prefix),
    );
    if (!matchesBand) return;

    final match = BandScanMatch(id: device.id, name: name, rssi: device.rssi);
    final existingIndex = _scanResults.indexWhere((d) => d.id == device.id);
    if (existingIndex == -1) {
      _scanResults.add(match);
    } else {
      _scanResults[existingIndex] = match;
    }
    notifyListeners();
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    if (!_disposed && _state == BandLinkState.scanning) {
      _state = BandLinkState.idle;
      notifyListeners();
    }
  }

  Future<void> connectTo(BandScanMatch device) async {
    await stopScan();
    _userInitiatedDisconnect = false;
    _reconnectAttempt = 0;
    _state = BandLinkState.connecting;
    notifyListeners();
    await _connect(device.id, device.name);
  }

  Future<void> forget() async {
    // Deliberately doesn't await the teardown below: the user is waiting
    // on this to flip the UI to "offline" right now, and neither
    // cancelling a BLE subscription nor clearing storage should be able
    // to stall that on a slow or unresponsive platform. _userInitiatedDisconnect
    // is set first so a late connection-state event arriving after this
    // still resolves to idle rather than triggering a reconnect.
    _userInitiatedDisconnect = true;
    _connectionGeneration++;
    _gattGeneration++;
    _batteryRefreshTimer?.cancel();
    _reconnectTimer?.cancel();
    configurationReady = false;
    _gatt = null;
    for (final subscription in _measurements) {
      unawaited(subscription.cancel());
    }
    _measurements.clear();
    // Cancelling the connection stream is how flutter_reactive_ble tears
    // down the link, there's no separate disconnect() call.
    final connectionSub = _connectionSub;
    _connectionSub = null;
    if (connectionSub != null) unawaited(connectionSub.cancel());
    unawaited(BandStorage.clearLastDevice());
    _deviceId = null;
    _deviceName = '';
    _clearReadings();
    _state = BandLinkState.idle;
    notifyListeners();
  }

  void _clearReadings() {
    _battery = -1;
    batteryAt = null;
    steps = null;
    stepsAt = null;
    _heartRate = null;
    heartRateAt = null;
    spo2Reading = null;
    firmwareVersion = null;
    mode = null;
    dailyIntervalMinutes = null;
    nightIntervalMinutes = null;
    readingIssue = null;
    _lastSeenAt = null;
  }

  @visibleForTesting
  Future<void> connectGattForTesting(String id) async {
    if (_gattFactory == null) throw StateError('Test transport required');
    if (_deviceId != id) _clearReadings();
    _deviceId = id;
    _deviceName = 'Umbra';
    _state = BandLinkState.connected;
    await _initializeGatt(id);
  }

  @visibleForTesting
  void dropForTesting() => _onLinkDropped(_deviceId ?? '', _deviceName);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _connectionGeneration++;
    _statusSub?.cancel();
    _scanSub?.cancel();
    _connectionSub?.cancel();
    _freshnessTimer?.cancel();
    _batteryRefreshTimer?.cancel();
    for (final subscription in _measurements) {
      unawaited(subscription.cancel());
    }
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
