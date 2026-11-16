import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactive_ble_platform_interface/reactive_ble_platform_interface.dart'
    show CharacteristicInstance;
import 'package:umbra/core/ble/band_gatt.dart';
import 'package:umbra/core/ble/band_protocol.dart';

class TestBle extends Fake implements FlutterReactiveBle {
  int discoveries = 0;
  final calls = <String>[];
  final readResult = Completer<List<int>>();

  @override
  Future<void> discoverAllServices(String deviceId) async => discoveries++;

  @override
  Future<List<int>> readCharacteristic(QualifiedCharacteristic characteristic) {
    calls.add('read');
    return readResult.future;
  }

  @override
  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) async {
    calls.add('write');
  }
}

class TestPlatform extends Fake implements ReactiveBlePlatform {
  final updates = StreamController<CharacteristicValue>.broadcast(sync: true);
  final acknowledgement = Completer<void>();
  final enabling = Completer<CharacteristicInstance>();
  final stopped = <CharacteristicInstance>[];

  @override
  Stream<CharacteristicValue> get charValueUpdateStream => updates.stream;

  @override
  Future<List<DiscoveredService>> getDiscoverServices(String deviceId) async =>
      [
        DiscoveredService(
          serviceId: Uuid.parse('180f'),
          serviceInstanceId: '0',
          characteristicIds: [Uuid.parse('2a19')],
          characteristics: [
            DiscoveredCharacteristic(
              characteristicId: Uuid.parse('2a19'),
              characteristicInstanceId: '0',
              serviceId: Uuid.parse('180f'),
              isReadable: true,
              isWritableWithResponse: false,
              isWritableWithoutResponse: false,
              isNotifiable: true,
              isIndicatable: false,
            ),
          ],
        ),
      ];

  @override
  Stream<void> subscribeToNotifications(CharacteristicInstance characteristic) {
    enabling.complete(characteristic);
    return acknowledgement.future.asStream();
  }

  @override
  Future<void> stopSubscribingToNotifications(
    CharacteristicInstance characteristic,
  ) async {
    stopped.add(characteristic);
  }
}

void main() {
  test(
    'iOS uses connection discovery; Android explicitly discovers services',
    () async {
      final ble = TestBle();
      final platform = TestPlatform();
      await ReactiveBandGatt(
        ble,
        'iphone',
        servicesAlreadyDiscovered: true,
        platform: platform,
      ).discover();
      expect(ble.discoveries, 0);
      await ReactiveBandGatt(ble, 'android', platform: platform).discover();
      expect(ble.discoveries, 1);
      await platform.updates.close();
    },
  );

  test(
    'notification readiness waits for native acknowledgement and retains immediate data',
    () async {
      final platform = TestPlatform();
      final gatt = ReactiveBandGatt(TestBle(), 'iphone', platform: platform);
      final received = <List<int>>[];
      final subscription = gatt
          .subscribe(BandProtocol.batteryService, BandProtocol.battery)
          .listen(received.add);
      var ready = false;
      final pending = gatt.notificationsReady().then((_) => ready = true);
      final address = await platform.enabling.future;
      expect(ready, isFalse);
      // iOS reports standard UUIDs in 16-bit form; retain the native instance IDs.
      expect(address.serviceId, Uuid.parse('180f'));
      platform.updates.add(
        CharacteristicValue(
          characteristic: address,
          result: const Result.success([78]),
        ),
      );
      platform.acknowledgement.complete();
      await pending;
      await Future<void>.delayed(Duration.zero);
      expect(received, [
        [78],
      ]);
      await subscription.cancel();
      expect(platform.stopped, [address]);
      await platform.updates.close();
    },
  );

  test(
    'native subscription failure fails readiness instead of enabling controls',
    () async {
      final platform = TestPlatform();
      final gatt = ReactiveBandGatt(TestBle(), 'iphone', platform: platform);
      final errors = <Object>[];
      final subscription = gatt
          .subscribe(BandProtocol.batteryService, BandProtocol.battery)
          .listen((_) {}, onError: errors.add);
      final check = expectLater(gatt.notificationsReady(), throwsStateError);
      await platform.enabling.future;
      platform.acknowledgement.completeError(StateError('CCCD rejected'));
      await check;
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      await subscription.cancel();
      await platform.updates.close();
    },
  );

  test('a command waits for a pending read', () async {
    final ble = TestBle();
    final platform = TestPlatform();
    final gatt = ReactiveBandGatt(ble, 'iphone', platform: platform);
    final read = gatt.read(BandProtocol.batteryService, BandProtocol.battery);
    final write = gatt.write(
      BandProtocol.service,
      BandProtocol.characteristic(3),
      [1],
    );
    await Future<void>.delayed(Duration.zero);
    expect(ble.calls, ['read']);
    ble.readResult.complete([78]);
    await read;
    await write;
    expect(ble.calls, ['read', 'write']);
    await platform.updates.close();
  });
}
