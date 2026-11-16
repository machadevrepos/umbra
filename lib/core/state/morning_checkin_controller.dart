import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/session_record.dart';
import '../notifications/checkin_notifications.dart';
import 'session_store.dart';
import 'settings_controller.dart';

DateTime morningCheckinTime(SessionRecord session) {
  final end = session.endedAt.toLocal();
  return DateTime(end.year, end.month, end.day + (end.hour >= 9 ? 1 : 0), 9);
}

class MorningCheckinController extends ChangeNotifier
    with WidgetsBindingObserver {
  MorningCheckinController({
    required SessionStore store,
    required SettingsController settings,
    CheckinNotifications? notifications,
    DateTime Function()? now,
  }) : _store = store,
       _settings = settings,
       _notifications = notifications ?? LocalCheckinNotifications(),
       _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
    _store.addListener(_changed);
    _settings.addListener(_changed);
    ready = _initialize();
  }

  final SessionStore _store;
  final SettingsController _settings;
  final CheckinNotifications _notifications;
  final DateTime Function() _now;
  late final Future<void> ready;
  Future<void> _operations = Future.value();
  bool _disposed = false;
  bool permissionGranted = false;
  bool busy = false;
  String? error;
  String? pendingSessionId;
  String? _scheduledKey;

  bool get enabled => _settings.notificationsEnabled && permissionGranted;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _initialize() async {
    await Future.wait([_store.ready, _settings.ready]);
    if (_disposed) return;
    try {
      final launchedId = await _notifications.initialize(_onTap);
      if (launchedId != null) pendingSessionId = launchedId;
      permissionGranted = await _notifications.hasPermission();
      await _synchronize();
    } catch (_) {
      error = 'Morning reminders could not be set up. Try again in Settings.';
    }
    _notify();
  }

  void _onTap(String sessionId) {
    pendingSessionId = sessionId;
    _notify();
  }

  String? takePendingSession() {
    final id = pendingSessionId;
    pendingSessionId = null;
    return id;
  }

  Future<void> setEnabled(bool value) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await ready;
      if (value) permissionGranted = await _notifications.requestPermission();
      _settings.setNotificationsEnabled(value && permissionGranted);
      if (value && !permissionGranted) {
        error =
            'Notifications are off. Allow them in your phone settings, then try again.';
      }
      await refresh();
      await _settings.flush();
    } catch (_) {
      error = 'The reminder could not be updated. Try again.';
    } finally {
      busy = false;
      _notify();
    }
  }

  void _changed() {
    unawaited(refresh());
  }

  Future<void> refresh() {
    _operations = _operations.then((_) async {
      await ready;
      if (_disposed) return;
      try {
        permissionGranted = await _notifications.hasPermission();
        await _synchronize();
      } catch (_) {
        error =
            'Your morning reminder could not be scheduled. Try again in Settings.';
      }
      _notify();
    });
    return _operations;
  }

  Future<void> _synchronize() async {
    final session = _store.mostRecent;
    if (!enabled || session == null || session.checkInRating != null) {
      await _notifications.cancel();
      _scheduledKey = null;
      return;
    }
    final at = morningCheckinTime(session);
    // A missed morning is available from history, without sending a second prompt tomorrow.
    if (!at.isAfter(_now())) return;
    final key = '${session.id}:$at:${at.timeZoneOffset}';
    if (_scheduledKey == key) return;
    await _notifications.schedule(session.id, at);
    _scheduledKey = key;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_changed);
    _settings.removeListener(_changed);
    super.dispose();
  }
}
