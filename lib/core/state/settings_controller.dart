import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App preferences retained across launches.
class SettingsController extends ChangeNotifier {
  SettingsController() {
    ready = _load();
  }
  late final Future<void> ready;
  bool _disposed = false;
  Future<void> _writes = Future.value();
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _notificationsEnabled =
          prefs.getBool('morning_notifications_enabled') ?? true;
      _hapticsEnabled = prefs.getBool('haptics_enabled') ?? true;
    } catch (_) {}
    if (!_disposed) notifyListeners();
  }

  void _save(String key, bool value) {
    _writes = _writes.then((_) async {
      try {
        await (await SharedPreferences.getInstance()).setBool(key, value);
      } catch (_) {}
    });
  }

  Future<void> flush() => _writes;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool _notificationsEnabled = true;
  bool _hapticsEnabled = true;

  bool get notificationsEnabled => _notificationsEnabled;
  bool get hapticsEnabled => _hapticsEnabled;

  void setNotificationsEnabled(bool value) {
    if (_notificationsEnabled == value) return;
    _notificationsEnabled = value;
    _save('morning_notifications_enabled', value);
    notifyListeners();
  }

  void setHapticsEnabled(bool value) {
    if (_hapticsEnabled == value) return;
    _hapticsEnabled = value;
    _save('haptics_enabled', value);
    notifyListeners();
  }
}
