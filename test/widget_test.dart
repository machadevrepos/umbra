import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra/core/ble/band_protocol.dart';
import 'package:umbra/core/constants/app_icons.dart';
import 'package:umbra/core/state/band_controller.dart';
import 'package:umbra/core/state/session_store.dart';
import 'package:umbra/core/utils/navigation.dart';
import 'package:umbra/main.dart';
import 'support/fake_band_gatt.dart';

Future<void> advance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
}

Future<void> home(
  WidgetTester tester,
  SessionStore store,
  BandController band,
) async {
  await tester.pumpWidget(UmbraApp(sessionStore: store, bandController: band));
  await tester.pump(const Duration(milliseconds: 950));
  await advance(tester);
  await advance(tester);
}

void main() {
  setUp(
    () =>
        SharedPreferences.setMockInitialValues({'onboarding_completed': true}),
  );
  testWidgets(
    'offline app has empty history and cannot start a dummy session',
    (tester) async {
      final store = SessionStore();
      await store.ready;
      final band = BandController(history: store, initialize: false);
      await home(tester, store, band);
      expect(find.text('Connect your band'), findsOneWidget);
      expect(find.text('Start session'), findsNothing);
      expect(store.history, isEmpty);
      await tester.tap(find.text('Night'));
      await advance(tester);
      expect(find.text('Session in progress'), findsNothing);
      await tester.tap(find.byIcon(AppIcons.history));
      await advance(tester);
      expect(find.text('Night session'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('first-run onboarding remains skippable without hardware', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = SessionStore();
    await store.ready;
    final band = BandController(history: store, initialize: false);
    await tester.pumpWidget(
      UmbraApp(sessionStore: store, bandController: band),
    );
    expect(find.text('UMBRA'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 950));
    await advance(tester);
    await advance(tester);
    await tester.tap(find.text('Skip'));
    await advance(tester);
    expect(find.text('A couple of permissions'), findsOneWidget);
    await tester.tap(find.text('Maybe later'));
    await advance(tester);
    expect(find.text('Find your band'), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    await advance(tester);
    expect(find.text('Connect your band'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'mode and interval controls write the band; active session has no simulated metrics',
    (tester) async {
      final store = SessionStore();
      await store.ready;
      final gatt = FakeBandGatt();
      final band = BandController(
        history: store,
        initialize: false,
        gattFactory: (_) => gatt,
      );
      await band.connectGattForTesting('test-band');
      await home(tester, store, band);
      expect(find.text('Reminds every 90 min'), findsOneWidget);
      await tester.tap(find.text('Night'));
      await advance(tester);
      expect(find.text('Session in progress'), findsOneWidget);
      expect(find.text('Reminds every 35 min'), findsOneWidget);
      await tester.tap(find.text('Reminds every 35 min'));
      await advance(tester);
      await tester.tap(find.text('Every 45 minutes'));
      await advance(tester);
      expect(band.nightIntervalMinutes, 45);
      await tester.tap(find.text('Session in progress'));
      await advance(tester);
      expect(find.text('No heart rate reading'), findsOneWidget);
      expect(find.text('HRV'), findsNothing);
      expect(find.text('Motion'), findsNothing);
      gatt.emit(BandProtocol.heart, [0, 88]);
      await advance(tester);
      expect(find.text('88'), findsOneWidget);
      await tester.tap(find.byIcon(AppIcons.chevronBack));
      await advance(tester);
      expect(find.text('Session in progress'), findsOneWidget);
      await tester.tap(find.text('Session in progress'));
      await advance(tester);
      await tester.dragUntilVisible(
        find.text('End session'),
        find.byType(ListView).last,
        const Offset(0, -150),
      );
      await tester.tap(find.text('End session'));
      await advance(tester);
      await tester.tap(find.text('End session').last);
      await advance(tester);
      await advance(tester);
      expect(band.mode!.name, 'daily');
      expect(store.history.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await gatt.close();
    },
  );
  testWidgets('band detail sends actual spot-check and haptic commands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SessionStore();
    await store.ready;
    final gatt = FakeBandGatt();
    final band = BandController(
      history: store,
      initialize: false,
      gattFactory: (_) => gatt,
    );
    await band.connectGattForTesting('test-band');
    await home(tester, store, band);
    await tester.tap(find.text('HEART RATE'));
    await advance(tester);
    expect(find.text('Firmware: 1.1.0'), findsOneWidget);
    gatt.emit(BandProtocol.characteristic(1), [123, 0, 0, 0]);
    await advance(tester);
    expect(find.text('STEPS SINCE POWER-ON'), findsOneWidget);
    expect(find.text('123'), findsOneWidget);
    await tester.tap(find.text('Measure SpO2'));
    await advance(tester);
    expect(gatt.writes.last.$1, BandProtocol.characteristic(9));
    await tester.ensureVisible(find.text('Test band vibration'));
    await advance(tester);
    await tester.tap(find.text('Test band vibration'));
    await advance(tester);
    expect(gatt.writes.last.$1, BandProtocol.characteristic(3));
    expect(gatt.writes.last.$2, [1]);
    await tester.pumpWidget(const SizedBox.shrink());
    await gatt.close();
  });
  testWidgets('history rating is attached to a hardware log session', (
    tester,
  ) async {
    final store = SessionStore();
    await store.ready;
    final time =
        DateTime.now()
            .subtract(const Duration(hours: 10))
            .toUtc()
            .millisecondsSinceEpoch ~/
        1000;
    await store.importBandLog(
      'test-band',
      [
        BandLogRecord(1, time, 42, 1, 88, 100, 60, 7, 97, 85),
        BandLogRecord(2, time + 60, 0, 1, 80, 90, 60, 1, 0, 0),
      ],
      3,
      currentlyNight: false,
    );
    final band = BandController(history: store, initialize: false);
    await home(tester, store, band);
    await tester.tap(find.byIcon(AppIcons.history));
    await advance(tester);
    await tester.tap(find.text('Night session'));
    await advance(tester);
    expect(find.text('STEPS'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    await tester.ensureVisible(find.text('Rate this night'));
    await tester.tap(find.text('Rate this night'));
    await advance(tester);
    await tester.tap(find.text('8'));
    await advance(tester);
    await tester.tap(find.text('Save'));
    await advance(tester);
    await advance(tester);
    expect(store.mostRecent!.checkInRating, 8);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('pushOnce prevents duplicate navigation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              pushOnce(context, (_) => const Text('first'));
              pushOnce(context, (_) => const Text('second'));
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsNothing);
  });
}
