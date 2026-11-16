import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra/core/ble/band_protocol.dart';
import 'package:umbra/core/models/hydration_mode.dart';
import 'package:umbra/core/permissions/band_permissions.dart';
import 'package:umbra/core/state/band_controller.dart';
import 'package:umbra/core/state/session_controller.dart';
import 'package:umbra/core/state/session_store.dart';
import 'support/fake_band_gatt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Android runtime permissions match the SDK', () {
    expect(BandPermissions.forAndroidSdk(30), [Permission.locationWhenInUse]);
    expect(BandPermissions.forAndroidSdk(31), [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ]);
  });
  test(
    'firmware codecs match documented little endian packets and zero HR means no reading',
    () {
      expect(BandProtocol.intervals(90, 45), [90, 0, 45, 0]);
      expect(BandProtocol.heartRate([0, 0]), isNull);
      expect(BandProtocol.heartRate([0, 84]), 84);
      expect(() => BandProtocol.intervals(90, 241), throwsFormatException);
      final sample = [
        0xd2,
        4,
        0,
        0,
        0x40,
        0xc1,
        0xed,
        0x6a,
        0x38,
        1,
        7,
        0,
        0x52,
        0x61,
        0x1e,
        5,
        0x61,
        0x55,
        0,
        0,
      ];
      final record = BandLogRecord.decode(sample, 20).single;
      expect(record.seq, 1234);
      expect(record.hrAvg, 82);
      expect(record.spo2, 97);
      expect(record.steps, 312);
      expect(record.durationSeconds, 300);
      expect(BandLogRecord.decode(sample.sublist(0, 16), 16).single.spo2, 0);
      expect(() => BandLogRecord.decode([1, 2, 3], 20), throwsFormatException);
    },
  );
  test(
    'app cannot start sessions without hardware; hardware notifications and commands control sessions',
    () async {
      final history = SessionStore();
      await history.ready;
      final transport = FakeBandGatt();
      final band = BandController(
        history: history,
        initialize: false,
        gattFactory: (_) => transport,
      );
      final session = SessionController(band: band, history: history);
      await session.ready;
      addTearDown(() async {
        session.dispose();
        band.dispose();
        history.dispose();
        await transport.close();
      });
      await expectLater(session.startSession(), throwsStateError);
      expect(session.isActive, isFalse);
      await band.connectGattForTesting('test-band');
      expect(band.configurationReady, isTrue);
      expect(transport.writes.first.$1, BandProtocol.characteristic(5));
      expect(band.mode, HydrationMode.daily);
      expect(band.nightIntervalMinutes, 35);
      await band.setInterval(HydrationMode.night, 45);
      expect(
        transport.writes
            .where((w) => w.$1 == BandProtocol.characteristic(4))
            .last
            .$2,
        [90, 0, 45, 0],
      );
      await session.startSession();
      expect(session.isActive, isTrue);
      transport.emit(BandProtocol.heart, [0, 80]);
      await Future<void>.delayed(Duration.zero);
      transport.emit(BandProtocol.heart, [0, 100]);
      await Future<void>.delayed(Duration.zero);
      expect(session.hr, 100);
      expect(session.avgHr, 90);
      transport.emit(BandProtocol.heart, [0, 0]);
      await Future<void>.delayed(Duration.zero);
      expect(session.hr, isNull);
      expect(session.avgHr, 90);
      transport.rejectWrites = true;
      await expectLater(
        band.setInterval(HydrationMode.night, 60),
        throwsStateError,
      );
      expect(band.nightIntervalMinutes, 45);
      transport.rejectWrites = false;
      await band.triggerHaptic();
      expect(transport.writes.last.$1, BandProtocol.characteristic(3));
      expect(transport.writes.last.$2, [1]);
      await session.endSession();
      await session.flush();
      expect(session.isActive, isFalse);
      expect(history.mostRecent!.deviceId, 'test-band');
      expect(history.mostRecent!.avgHrv, isNull);
      expect(history.mostRecent!.reminderCount, isNull);
    },
  );
  test(
    'physical mode changes create a session, and disconnect makes readings unavailable',
    () async {
      final history = SessionStore();
      await history.ready;
      final transport = FakeBandGatt();
      final band = BandController(
        history: history,
        initialize: false,
        gattFactory: (_) => transport,
      );
      final session = SessionController(band: band, history: history);
      await session.ready;
      await band.connectGattForTesting('test-band');
      transport.emit(BandProtocol.characteristic(2), [1]);
      await Future<void>.delayed(Duration.zero);
      expect(session.isActive, isTrue);
      transport.emit(BandProtocol.heart, [0, 85]);
      await Future<void>.delayed(Duration.zero);
      expect(session.hr, 85);
      band.dropForTesting();
      expect(session.hr, isNull);
      expect(band.canControl, isFalse);
      await expectLater(band.measureSpo2(), throwsStateError);
      session.dispose();
      band.dispose();
      history.dispose();
      await transport.close();
    },
  );
  test(
    'firmware logs persist and deduplicate across syncs; UTC-less records have no invented dates',
    () async {
      final store = SessionStore();
      await store.ready;
      final time =
          DateTime(2026, 11, 9, 1).toUtc().millisecondsSinceEpoch ~/ 1000;
      final records = [
        BandLogRecord(1, time, 2, 1, 80, 90, 60, 3, 97, 85),
        BandLogRecord(2, time + 60, 3, 1, 90, 99, 60, 3, 0, 0),
        BandLogRecord(3, time + 120, 0, 1, 75, 80, 60, 1, 0, 0),
      ];
      await store.importBandLog('hardware', records, 4, currentlyNight: false);
      expect(store.history.length, 1);
      expect(store.mostRecent!.avgHr, 85);
      await store.attachCheckIn(store.mostRecent!.id, 8);
      await store.importBandLog('hardware', records, 4, currentlyNight: false);
      expect(store.history.length, 1);
      expect(store.mostRecent!.checkInRating, 8);
      expect(await store.logCursor('hardware'), 4);
      final loaded = SessionStore();
      await loaded.ready;
      expect(loaded.mostRecent!.checkInRating, 8);
      await loaded.importBandLog(
        'untimed',
        [const BandLogRecord(1, 60, 0, 2, 80, 90, 60, 2, 0, 0)],
        2,
        currentlyNight: false,
      );
      expect(loaded.history.length, 1);
      store.dispose();
      loaded.dispose();
    },
  );
  test('heart rate expires after three seconds without another real notification',() async {
    final store=SessionStore();await store.ready;
    final gatt=FakeBandGatt();final band=BandController(history:store,initialize:false,gattFactory:(_)=>gatt);
    await band.connectGattForTesting('test-band');
    gatt.emit(BandProtocol.heart,[0,88]);await Future<void>.delayed(Duration.zero);
    expect(band.heartRate,88);
    await Future<void>.delayed(const Duration(milliseconds:3100));
    expect(band.heartRate,isNull);
    band.dispose();store.dispose();await gatt.close();
  });
  test('an incomplete log transfer never advances the saved hardware cursor',() async {
    final store=SessionStore();await store.ready;
    final gatt=FakeBandGatt();
    gatt.values[BandProtocol.characteristic(7)]=[1,0,0,0,3,0,0,0,0,4,20,2];
    gatt.logPackets.add([1,0,0,0,0x40,0xc1,0xed,0x6a,0,0,1,0,80,90,6,3,97,85,0,0]);
    final band=BandController(history:store,initialize:false,gattFactory:(_)=>gatt);
    await band.connectGattForTesting('test-band');await Future<void>.delayed(const Duration(milliseconds:20));
    expect(await store.logCursor('test-band'),0);
    expect(store.history,isEmpty);
    expect(band.deviceError,contains('incomplete'));
    band.dispose();store.dispose();await gatt.close();
  });

}
