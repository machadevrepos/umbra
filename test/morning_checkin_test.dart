import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra/core/models/hydration_mode.dart';
import 'package:umbra/core/models/session_record.dart';
import 'package:umbra/core/notifications/checkin_notifications.dart';
import 'package:umbra/core/state/morning_checkin_controller.dart';
import 'package:umbra/core/state/session_store.dart';
import 'package:umbra/core/state/settings_controller.dart';

class FakeNotifications implements CheckinNotifications {
  bool permitted = true;
  int schedules = 0;
  int cancellations = 0;
  String? scheduledId;
  DateTime? at;
  String? launch;
  late void Function(String) tap;
  @override
  Future<String?> initialize(void Function(String) onTap) async {
    tap = onTap;
    return launch;
  }

  @override
  Future<bool> hasPermission() async => permitted;
  @override
  Future<bool> requestPermission() async => permitted;
  @override
  Future<void> cancel() async {
    cancellations++;
    scheduledId = null;
  }

  @override
  Future<void> schedule(String sessionId, DateTime time) async {
    schedules++;
    scheduledId = sessionId;
    at = time;
  }
}

SessionRecord night(String id, DateTime end) => SessionRecord(
  id: id,
  deviceId: 'test-band',
  mode: HydrationMode.night,
  startedAt: end.subtract(const Duration(hours: 2)),
  endedAt: end,
  avgHr: 88,
  avgHrv: null,
  avgSpo2: 97,
  motion: 'No data',
  reminderCount: 3,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'sessions ending before 9 use this morning; later sessions use tomorrow',
    () {
      expect(
        morningCheckinTime(night('one', DateTime(2026, 11, 9, 2))),
        DateTime(2026, 11, 9, 9),
      );
      expect(
        morningCheckinTime(night('two', DateTime(2026, 11, 9, 23))),
        DateTime(2026, 11, 10, 9),
      );
    },
  );

  test(
    'one morning notification, cancellation on rating, and warm/cold tap payloads',
    () async {
      final store = SessionStore();
      final settings = SettingsController();
      await Future.wait([store.ready, settings.ready]);
      await store.addSession(night('night-one', DateTime(2026, 11, 9, 2)));
      final gateway = FakeNotifications()..launch = 'night-one';
      final controller = MorningCheckinController(
        store: store,
        settings: settings,
        notifications: gateway,
        now: () => DateTime(2026, 11, 9, 3),
      );
      await controller.ready;
      expect(gateway.schedules, 1);
      expect(gateway.at, DateTime(2026, 11, 9, 9));
      expect(controller.takePendingSession(), 'night-one');
      expect(controller.takePendingSession(), isNull);
      gateway.tap('night-one');
      expect(controller.takePendingSession(), 'night-one');
      await controller.refresh();
      await controller.refresh();
      expect(gateway.schedules, 1);
      await store.attachCheckIn('night-one', 8);
      await controller.refresh();
      expect(gateway.scheduledId, isNull);
      controller.dispose();
      store.dispose();
      settings.dispose();
    },
  );

  test(
    'denied permission and disabled preference never schedule; missed nights do not re-prompt',
    () async {
      final store = SessionStore();
      final settings = SettingsController();
      await Future.wait([store.ready, settings.ready]);
      await store.addSession(night('old', DateTime(2026, 11, 8, 2)));
      final gateway = FakeNotifications()..permitted = false;
      final controller = MorningCheckinController(
        store: store,
        settings: settings,
        notifications: gateway,
        now: () => DateTime(2026, 11, 9, 3),
      );
      await controller.ready;
      await controller.setEnabled(true);
      expect(controller.enabled, isFalse);
      expect(controller.error, contains('Notifications are off'));
      expect(gateway.schedules, 0);
      gateway.permitted = true;
      await controller.setEnabled(true);
      expect(gateway.schedules, 0);
      await store.addSession(night('new', DateTime(2026, 11, 9, 2)));
      await controller.refresh();
      expect(gateway.schedules, 1);
      await controller.setEnabled(false);
      expect(gateway.scheduledId, isNull);
      controller.dispose();
      store.dispose();
      settings.dispose();
    },
  );
}
