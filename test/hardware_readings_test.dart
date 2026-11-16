import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra/core/ble/band_database.dart';
import 'package:umbra/core/ble/band_protocol.dart';
import 'package:umbra/core/state/band_controller.dart';
import 'package:umbra/core/state/session_controller.dart';
import 'package:umbra/core/state/session_store.dart';
import 'support/fake_band_gatt.dart';

List<int> stepPacket(int count) =>
    (ByteData(4)..setUint32(0, count, Endian.little)).buffer.asUint8List();
Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'setup waits for notification acknowledgement before history or controls',
    () async {
      final store = SessionStore();
      await store.ready;
      final acknowledgement = Completer<void>();
      final gatt = FakeBandGatt()..notificationSetup = acknowledgement.future;
      final band = BandController(
        history: store,
        initialize: false,
        gattFactory: (_) => gatt,
      );
      final connection = band.connectGattForTesting('iphone');
      await tick();
      expect(band.connected, isTrue);
      expect(band.canControl, isFalse);
      expect(
        gatt.writes.where((w) => w.$1 == BandProtocol.characteristic(7)),
        isEmpty,
      );
      acknowledgement.complete();
      await connection;
      expect(band.canControl, isTrue);
      expect(
        gatt.writes.where((w) => w.$1 == BandProtocol.characteristic(7)),
        hasLength(1),
      );
      await band.flushReadings();
      band.dispose();
      store.dispose();
      await gatt.close();
    },
  );

  test(
    'subscription errors during initial reads cannot be overwritten by ready state',
    () async {
      final store = SessionStore();
      await store.ready;
      final gatt = FakeBandGatt();
      gatt.onRead = (characteristic) async {
        if (characteristic == BandProtocol.characteristic(2)) {
          gatt.streams[BandProtocol.heart]!.addError(
            StateError('Native notifications failed'),
          );
          await tick();
        }
        return List.of(gatt.values[characteristic]!);
      };
      final band = BandController(
        history: store,
        initialize: false,
        gattFactory: (_) => gatt,
      );
      await band.connectGattForTesting('iphone');
      expect(band.canControl, isFalse);
      expect(band.deviceError, contains('keep band readings active'));
      band.dispose();
      store.dispose();
      await gatt.close();
    },
  );

  Future<(SessionStore, FakeBandGatt, BandController)> connected() async {
    final store = SessionStore();
    await store.ready;
    final gatt = FakeBandGatt();
    gatt.values[BandProtocol.battery] = [95];
    final band = BandController(
      history: store,
      initialize: false,
      gattFactory: (_) => gatt,
    );
    addTearDown(() async {
      await band.flushReadings();
      band.dispose();
      store.dispose();
      await gatt.close();
    });
    await band.connectGattForTesting('band');
    await band.flushReadings();
    return (store, gatt, band);
  }

  test(
    '95 to zero notification is verified; a real empty battery is accepted',
    () async {
      final (_, gatt, band) = await connected();
      final confirmation = Completer<List<int>>();
      gatt.onRead = (_) => confirmation.future;
      gatt.emit(BandProtocol.battery, [0]);
      await tick();
      expect(band.battery, 95);
      confirmation.complete([95]);
      await tick();
      expect(band.battery, 95);
      gatt.onRead = (_) async => [0];
      gatt.emit(BandProtocol.battery, [0]);
      await tick();
      expect(band.battery, 0);
      expect(band.readingIssue, isNull);
    },
  );

  test(
    'new notification wins over delayed battery verification and poll',
    () async {
      final (_, gatt, band) = await connected();
      final response = Completer<List<int>>();
      gatt.onRead = (_) => response.future;
      final poll = band.refreshBattery();
      gatt.emit(BandProtocol.battery, [96]);
      await tick();
      response.complete([0]);
      await poll;
      expect(band.battery, 96);
    },
  );

  test(
    'failed confirmation and malformed packets retain last valid readings',
    () async {
      final (_, gatt, band) = await connected();
      gatt.onRead = (_) async => throw StateError('Read failed');
      gatt.emit(BandProtocol.battery, [0]);
      await tick();
      expect(band.battery, 95);
      expect(band.readingIssue, contains('could not be verified'));
      gatt.emit(BandProtocol.battery, [255]);
      gatt.emit(BandProtocol.characteristic(1), [1]);
      gatt.emit(BandProtocol.characteristic(9), [0]);
      await tick();
      expect(band.battery, 95);
      expect(band.steps, 0);
      expect(band.configurationReady, isTrue);
    },
  );

  test('connect-time reads cannot overwrite newer notifications', () async {
    final (_, gatt, band) = await connected();
    final steps = BandProtocol.characteristic(1);
    gatt.onRead = (characteristic) async {
      final old = List.of(gatt.values[characteristic]!);
      if (characteristic == BandProtocol.battery) {
        gatt.emit(characteristic, [97]);
      }
      if (characteristic == steps) gatt.emit(characteristic, stepPacket(125));
      await tick();
      return old;
    };
    await band.retryInitialization();
    expect(band.battery, 97);
    expect(band.steps, 125);
    await band.flushReadings();
  });

  test('pending battery reads do not update a disconnected band', () async {
    final (_, gatt, band) = await connected();
    final response = Completer<List<int>>();
    gatt.onRead = (_) => response.future;
    final poll = band.refreshBattery();
    band.dropForTesting();
    response.complete([0]);
    await poll;
    expect(band.battery, 95);
    expect(band.connected, isFalse);
  });

  test(
    'late initialization cannot restore readings after forgetting a band',
    () async {
      final (_, gatt, band) = await connected();
      final response = Completer<List<int>>();
      final reading = Completer<void>();
      gatt.onRead = (_) {
        if (!reading.isCompleted) reading.complete();
        return response.future;
      };
      final initialization = band.retryInitialization();
      await reading.future;
      await band.forget();
      response.complete([1]);
      await initialization;
      expect(band.battery, -1);
      expect(band.steps, isNull);
      expect(band.mode, isNull);
      expect(band.spo2Reading, isNull);
      expect(band.configurationReady, isFalse);
    },
  );

  test(
    'counter reset never produces negative session steps or erases stored logs',
    () async {
      final (store, gatt, band) = await connected();
      final session = SessionController(band: band, history: store);
      await session.ready;
      addTearDown(session.dispose);
      gatt.emit(BandProtocol.characteristic(1), stepPacket(100));
      await tick();
      await session.startSession();
      gatt.emit(BandProtocol.characteristic(1), stepPacket(5));
      await tick();
      expect(session.steps, isNull);
      gatt.emit(BandProtocol.characteristic(1), stepPacket(120));
      await tick();
      expect(session.steps, isNull);
      await band.flushReadings();
      expect((await store.bandDatabase.lastSteps('band'))!.steps, 120);
      await session.endSession();
      await session.flush();
      expect(store.mostRecent!.steps, isNull);
    },
  );

  test(
    'live steps persist in SQLite and session delta survives serialization',
    () async {
      final (store, gatt, band) = await connected();
      gatt.emit(BandProtocol.characteristic(1), stepPacket(100));
      await tick();
      final session = SessionController(band: band, history: store);
      await session.ready;
      addTearDown(session.dispose);
      await session.startSession();
      gatt.emit(BandProtocol.characteristic(1), stepPacket(145));
      await tick();
      expect(session.steps, 45);
      await session.endSession();
      await session.flush();
      await band.flushReadings();
      await BandDatabase.close();
      final saved = await BandDatabase().lastSteps('band');
      expect(saved!.steps, 145);
      final reloaded = SessionStore();
      await reloaded.ready;
      expect(reloaded.mostRecent!.steps, 45);
      await reloaded.attachCheckIn(reloaded.mostRecent!.id, 8);
      expect(reloaded.mostRecent!.steps, 45);
      reloaded.dispose();
    },
  );

  test(
    'log steps include Daily, deduplicate, respect validity and migrate preferences',
    () async {
      const time = 1793966400;
      const records = [
        BandLogRecord(1, time, 100, 1, 80, 90, 300, 5, 0, 0),
        BandLogRecord(2, time + 300, 12, 1, 80, 90, 60, 7, 0, 0),
        BandLogRecord(3, time + 360, 18, 1, 90, 99, 60, 7, 0, 0),
        BandLogRecord(4, time + 420, 0, 1, 75, 80, 300, 5, 0, 0),
      ];
      SharedPreferences.setMockInitialValues({
        'band_log_v2_band': jsonEncode({
          'records': records.map((r) => r.toJson()).toList(),
          'next': 5,
        }),
      });
      final store = SessionStore();
      await store.ready;
      expect(await store.logCursor('band'), 5);
      await store.importBandLog('band', [], 5, currentlyNight: false);
      expect(store.mostRecent!.steps, 30);
      await store.importBandLog('band', records, 5, currentlyNight: false);
      expect(store.history.length, 1);
      await BandDatabase.close();
      expect((await BandDatabase().logs('band')).length, 4);
      expect((await BandDatabase().logs('band')).first.steps, 100);
      expect(
        (await SharedPreferences.getInstance()).containsKey('band_log_v2_band'),
        isFalse,
      );
      await store.importBandLog(
        'band',
        [const BandLogRecord(3, time + 360, 999, 1, 90, 99, 60, 3, 0, 0)],
        5,
        currentlyNight: false,
      );
      expect(store.mostRecent!.steps, isNull);
      store.dispose();
    },
  );
}
