import 'package:flutter/foundation.dart';

/// Band connection state shared between Home's status pill and the
/// upcoming Band Detail screen. Mock values today; swaps for the real BLE
/// connection stream once that layer exists, the read shape (connected,
/// battery, restingHr) is what every screen actually needs regardless of
/// where it comes from.
class BandController extends ChangeNotifier {
  bool _connected = true;
  int _battery = 82;
  int _restingHr = 68;

  bool get connected => _connected;
  int get battery => _battery;
  int get restingHr => _restingHr;

  void setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    notifyListeners();
  }

  void setBattery(int value) {
    if (_battery == value) return;
    _battery = value;
    notifyListeners();
  }

  void setRestingHr(int value) {
    if (_restingHr == value) return;
    _restingHr = value;
    notifyListeners();
  }
}
