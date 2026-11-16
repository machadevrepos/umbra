import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

abstract interface class CheckinNotifications {
  Future<String?> initialize(void Function(String) onTap);
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<void> schedule(String sessionId, DateTime at);
  Future<void> cancel();
}

class LocalCheckinNotifications implements CheckinNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool get _supported => Platform.isAndroid || Platform.isIOS;
  static const int notificationId = 900;

  @override
  Future<String?> initialize(void Function(String) onTap) async {
    if (!_supported) return null;
    tz_data.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_umbra'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) onTap(response.payload!);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp == true
        ? launch?.notificationResponse?.payload
        : null;
  }

  @override
  Future<bool> hasPermission() async {
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled() ??
          false;
    }
    if (Platform.isIOS) {
      return (await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.checkPermissions())
              ?.isEnabled ??
          false;
    }
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true, badge: false) ??
          false;
    }
    return false;
  }

  @override
  Future<void> schedule(String sessionId, DateTime at) async {
    if (!_supported) return;
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    await _plugin.zonedSchedule(
      notificationId,
      'Morning check-in',
      'How do you feel, 1–10?',
      tz.TZDateTime(tz.local, at.year, at.month, at.day, 9),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'morning_checkin',
          'Morning check-in',
          channelDescription: 'One morning prompt after a tracked night.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(presentBadge: false),
      ),
      // Avoid requiring special alarm access for a wellness check-in.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: sessionId,
    );
  }

  @override
  Future<void> cancel() async {
    if (_supported) await _plugin.cancel(notificationId);
  }
}
