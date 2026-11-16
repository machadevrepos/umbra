import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:reactive_ble_platform_interface/reactive_ble_platform_interface.dart'
    show CharacteristicInstance;

abstract interface class BandGatt {
  Future<void> discover();
  Future<List<int>> read(String service, String characteristic);
  Future<void> write(String service, String characteristic, List<int> value);
  Stream<List<int>> subscribe(String service, String characteristic);
  Future<void> notificationsReady();
}

class ReactiveBandGatt implements BandGatt {
  ReactiveBandGatt(
    this.ble,
    this.deviceId, {
    this.servicesAlreadyDiscovered = false,
    ReactiveBlePlatform? platform,
  }) : _platform = platform ?? ReactiveBlePlatform.instance;
  final FlutterReactiveBle ble;
  final String deviceId;
  final bool servicesAlreadyDiscovered;
  final ReactiveBlePlatform _platform;
  Future<void> _operations = Future.value();
  final List<Future<void>> _subscriptions = [];

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _operations.then(
      (_) => action().timeout(const Duration(seconds: 8)),
    );
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  QualifiedCharacteristic _characteristic(
    String service,
    String characteristic,
  ) => QualifiedCharacteristic(
    serviceId: Uuid.parse(service),
    characteristicId: Uuid.parse(characteristic),
    deviceId: deviceId,
  );
  @override
  Future<void> discover() async {
    // On iOS the plugin emits connected after its initial discovery completes.
    if (!servicesAlreadyDiscovered) await ble.discoverAllServices(deviceId);
  }

  @override
  Future<List<int>> read(String service, String characteristic) => _enqueue(
    () => ble.readCharacteristic(_characteristic(service, characteristic)),
  );
  @override
  Future<void> write(String service, String characteristic, List<int> value) =>
      _enqueue(
        () => ble.writeCharacteristicWithResponse(
          _characteristic(service, characteristic),
          value: value,
        ),
      );
  @override
  Stream<List<int>> subscribe(String service, String characteristic) {
    final ready = Completer<void>();
    _subscriptions.add(ready.future);
    // Attach an error handler immediately, before notificationsReady is awaited.
    unawaited(ready.future.catchError((Object _) {}));
    StreamSubscription<CharacteristicValue>? updates;
    CharacteristicInstance? address;
    var cancelled = false;
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        unawaited(
          _enqueue(() async {
            final services = await _platform.getDiscoverServices(deviceId);
            final matches = services
                .where(
                  (s) => s.serviceId.expanded == Uuid.parse(service).expanded,
                )
                .expand((s) => s.characteristics.map((c) => (s, c)))
                .where(
                  (c) =>
                      c.$2.characteristicId.expanded ==
                      Uuid.parse(characteristic).expanded,
                )
                .toList();
            if (matches.length != 1) {
              throw StateError(
                'Notification characteristic not found: $characteristic',
              );
            }
            if (cancelled) throw StateError('Subscription cancelled');
            final (matchedService, match) = matches.single;
            final resolved = CharacteristicInstance(
              deviceId: deviceId,
              serviceId: match.serviceId,
              serviceInstanceId: matchedService.serviceInstanceId,
              characteristicId: match.characteristicId,
              characteristicInstanceId: match.characteristicInstanceId,
            );
            address = resolved;
            updates = _platform.charValueUpdateStream
                .where((value) => value.characteristic == resolved)
                .listen(
                  (value) {
                    if (cancelled) return;
                    try {
                      controller.add(value.result.dematerialize());
                    } catch (error, stack) {
                      controller.addError(error, stack);
                    }
                  },
                  onError: (Object error, StackTrace stack) {
                    if (!cancelled) controller.addError(error, stack);
                  },
                );
            // CoreBluetooth acknowledges CCCD setup asynchronously. Listening alone
            // does not mean the band is ready to send its history notifications.
            await _platform.subscribeToNotifications(resolved).first;
          }).then(
            (_) {
              ready.complete();
            },
            onError: (Object error, StackTrace stack) {
              ready.completeError(error, stack);
              if (!cancelled) controller.addError(error, stack);
            },
          ),
        );
      },
      onCancel: () async {
        cancelled = true;
        await updates?.cancel();
        final resolved = address;
        if (resolved != null) {
          try {
            await _enqueue(
              () => _platform.stopSubscribingToNotifications(resolved),
            );
          } catch (_) {
            // A dropped connection has already removed its notification state.
          }
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> notificationsReady() async {
    await Future.wait(_subscriptions, eagerError: true);
  }
}
