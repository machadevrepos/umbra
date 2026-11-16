import 'hydration_mode.dart';

/// A completed session, whether a Night Mode "night out" or a slice of
/// passive Daily Mode tracking. Immutable, `copyWith` for the one mutation
/// that happens after the fact: attaching the next morning's check-in.
///
/// Only [HydrationMode.night] is produced today: Daily Mode is ambient,
/// with nothing to "start" or "end" (see the comment on `_PrimaryAction`
/// in home_screen.dart), so no code path builds a daily [SessionRecord]
/// yet. [mode] stays a real [HydrationMode] rather than being hardcoded to
/// night, and `HistoryRow`/session cards branch on it correctly, because a
/// future Daily Mode digest is a plausible feature, not a hypothetical one
/// worth deleting the handling for.
class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.mode,
    required this.startedAt,
    required this.endedAt,
    required this.avgHr,
    required this.avgHrv,
    required this.avgSpo2,
    required this.motion,
    required this.reminderCount,
    this.checkInRating,
    this.deviceId,
    this.steps,
  });

  final String id;
  final HydrationMode mode;
  final DateTime startedAt;
  final DateTime endedAt;
  final int? avgHr;
  final int? avgHrv;
  final int? avgSpo2;
  final String motion;
  final int? reminderCount;
  final String? deviceId;
  final int? checkInRating;
  final int? steps;

  String get stepsLabel => steps == null ? 'No data' : '$steps';

  String get avgHrLabel => avgHr == null ? 'No data' : '$avgHr bpm';
  String get avgHrvLabel => avgHrv == null ? 'No data' : '$avgHrv ms';
  String get avgSpo2Label => avgSpo2 == null ? 'No data' : '$avgSpo2%';

  Map<String, dynamic> toJson() => {
    'id': id,
    'mode': mode.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'avgHr': avgHr,
    'avgHrv': avgHrv,
    'avgSpo2': avgSpo2,
    'motion': motion,
    'reminderCount': reminderCount,
    'checkInRating': checkInRating,
    'deviceId': deviceId,
    'steps': steps,
  };

  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
    id: json['id'] as String,
    mode: HydrationMode.values.byName(json['mode'] as String),
    startedAt: DateTime.parse(json['startedAt'] as String).toLocal(),
    endedAt: DateTime.parse(json['endedAt'] as String).toLocal(),
    avgHr: json['avgHr'] as int?,
    avgHrv: json['avgHrv'] as int?,
    avgSpo2: json['avgSpo2'] as int?,
    motion: json['motion'] as String,
    reminderCount: json['reminderCount'] as int?,
    checkInRating: json['checkInRating'] as int?,
    deviceId: json['deviceId'] as String?,
    steps: json['steps'] as int?,
  );

  Duration get duration => endedAt.difference(startedAt);

  String get durationLabel {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  SessionRecord copyWith({int? checkInRating}) {
    return SessionRecord(
      id: id,
      mode: mode,
      startedAt: startedAt,
      endedAt: endedAt,
      avgHr: avgHr,
      avgHrv: avgHrv,
      avgSpo2: avgSpo2,
      motion: motion,
      reminderCount: reminderCount,
      checkInRating: checkInRating ?? this.checkInRating,
      deviceId: deviceId,
      steps: steps,
    );
  }
}
