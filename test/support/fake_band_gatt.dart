import 'dart:async';
import 'dart:convert';
import 'package:umbra/core/ble/band_gatt.dart';
import 'package:umbra/core/ble/band_protocol.dart';

// Test-only protocol peer. Production always uses ReactiveBandGatt.
class FakeBandGatt implements BandGatt {
  final values = <String, List<int>>{
    BandProtocol.characteristic(1): [0, 0, 0, 0],
    BandProtocol.characteristic(2): [0],
    BandProtocol.characteristic(4): [90, 0, 35, 0],
    BandProtocol.characteristic(6): [100, 5, 164, 1],
    BandProtocol.characteristic(7): [1, 0, 0, 0, 1, 0, 0, 0, 0, 4, 20, 2],
    BandProtocol.characteristic(9): List.filled(10, 0),
    BandProtocol.battery: [78],
    BandProtocol.firmware: utf8.encode('1.1.0'),
  };
  final streams = <String, StreamController<List<int>>>{};
  final writes = <(String, List<int>)>[];
  bool rejectWrites = false;
  final logPackets = <List<int>>[];
  Future<List<int>> Function(String characteristic)? onRead;
  Future<void>? notificationSetup;
  @override
  Future<void> discover() async {}
  @override
  Future<void> notificationsReady() async {
    await notificationSetup;
  }

  @override
  Future<List<int>> read(String service, String characteristic) async =>
      onRead == null
      ? List.of(values[characteristic]!)
      : await onRead!(characteristic);
  @override
  Stream<List<int>> subscribe(String service, String characteristic) => streams
      .putIfAbsent(
        characteristic,
        () => StreamController<List<int>>.broadcast(),
      )
      .stream;
  void emit(String characteristic, List<int> value) {
    values[characteristic] = List.of(value);
    streams[characteristic]?.add(value);
  }

  @override
  Future<void> write(
    String service,
    String characteristic,
    List<int> value,
  ) async {
    if (rejectWrites) throw StateError('Firmware rejected write');
    writes.add((characteristic, List.of(value)));
    if (characteristic == BandProtocol.characteristic(2) ||
        characteristic == BandProtocol.characteristic(4)) {
      emit(characteristic, value);
    }
    if (characteristic == BandProtocol.characteristic(7)) {
      for (final packet in logPackets) {
        emit(BandProtocol.characteristic(8), packet);
      }
      emit(
        BandProtocol.characteristic(8),
        values[BandProtocol.characteristic(7)]!.sublist(4, 8),
      );
    }
    if (characteristic == BandProtocol.characteristic(9)) {
      emit(characteristic, [2, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    }
  }

  Future<void> close() async {
    for (final s in streams.values) {
      await s.close();
    }
  }
}
