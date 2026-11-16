import 'dart:typed_data';
import '../models/hydration_mode.dart';

class BandProtocol {
  const BandProtocol._();
  static const service = '1ab10000-fde9-42a3-ab5b-82416f9bca6e';
  static const heartService = '0000180d-0000-1000-8000-00805f9b34fb';
  static const heart = '00002a37-0000-1000-8000-00805f9b34fb';
  static const batteryService = '0000180f-0000-1000-8000-00805f9b34fb';
  static const battery = '00002a19-0000-1000-8000-00805f9b34fb';
  static const infoService = '0000180a-0000-1000-8000-00805f9b34fb';
  static const firmware = '00002a26-0000-1000-8000-00805f9b34fb';
  static String characteristic(int n) =>
      '1ab1000$n-fde9-42a3-ab5b-82416f9bca6e';
  static ByteData bytes(List<int> value) =>
      ByteData.sublistView(Uint8List.fromList(value));
  static int? heartRate(List<int> value) {
    if (value.length < 2) throw const FormatException('Incomplete heart rate');
    final wide = value[0] & 1 != 0;
    if (wide && value.length < 3) {
      throw const FormatException('Incomplete heart rate');
    }
    final hr = wide ? bytes(value).getUint16(1, Endian.little) : value[1];
    return hr == 0 ? null : hr;
  }

  static HydrationMode mode(List<int> value) {
    if (value.length != 1 || value.single > 1) {
      throw const FormatException('Invalid mode');
    }
    return value.single == 0 ? HydrationMode.daily : HydrationMode.night;
  }

  static List<int> time(DateTime now) {
    final data = ByteData(6)
      ..setUint32(0, now.toUtc().millisecondsSinceEpoch ~/ 1000, Endian.little)
      ..setInt16(4, now.timeZoneOffset.inMinutes, Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> intervals(int daily, int night) {
    if (daily < 0 || daily > 240 || night < 0 || night > 240) {
      throw const FormatException('Invalid interval');
    }
    return (ByteData(4)
          ..setUint16(0, daily, Endian.little)
          ..setUint16(2, night, Endian.little))
        .buffer
        .asUint8List();
  }

  static List<int> logRequest(int sequence) =>
      (ByteData(4)..setUint32(0, sequence, Endian.little)).buffer.asUint8List();
}

class BandSpo2Reading {
  const BandSpo2Reading(
    this.status,
    this.percent,
    this.quality,
    this.measuredAt,
  );
  final int status;
  final int? percent;
  final int quality;
  final DateTime? measuredAt;
  factory BandSpo2Reading.decode(List<int> value) {
    if (value.length != 10 ||
        value[0] > 7 ||
        value[1] > 100 ||
        value[2] > 100) {
      throw const FormatException('Invalid SpO2 reading');
    }
    final seconds = BandProtocol.bytes(value).getUint32(4, Endian.little);
    return BandSpo2Reading(
      value[0],
      value[1] == 0 ? null : value[1],
      value[2],
      seconds == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              seconds * 1000,
              isUtc: true,
            ).toLocal(),
    );
  }
  bool isRecent(DateTime now) =>
      percent != null &&
      measuredAt != null &&
      now.difference(measuredAt!).inSeconds >= 0 &&
      now.difference(measuredAt!) <= const Duration(minutes: 35);
  String get statusLabel => const [
    'No measurement yet',
    'Reading available',
    'Measuring. Keep your wrist still.',
    'Place the band on your skin.',
    'Too much movement. Keep still and retry.',
    'Pulse too weak. Adjust the band and retry.',
    'Signal unstable. Keep still and retry.',
    'SpO2 sensor unavailable.',
  ][status];
}

class BandLogRecord {
  const BandLogRecord(
    this.seq,
    this.time,
    this.steps,
    this.boot,
    this.hrAvg,
    this.hrMax,
    this.durationSeconds,
    this.flags,
    this.spo2,
    this.spo2Quality,
  );
  final int seq,
      time,
      steps,
      boot,
      hrAvg,
      hrMax,
      durationSeconds,
      flags,
      spo2,
      spo2Quality;
  bool get timeIsUtc => flags & 1 != 0;
  bool get night => flags & 2 != 0;
  bool get stepsValid => flags & 4 != 0;
  DateTime get startedAt =>
      DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true).toLocal();
  DateTime get endedAt => startedAt.add(Duration(seconds: durationSeconds));
  List<int> toJson() => [
    seq,
    time,
    steps,
    boot,
    hrAvg,
    hrMax,
    durationSeconds,
    flags,
    spo2,
    spo2Quality,
  ];
  factory BandLogRecord.fromJson(List<dynamic> v) => BandLogRecord(
    v[0] as int,
    v[1] as int,
    v[2] as int,
    v[3] as int,
    v[4] as int,
    v[5] as int,
    v[6] as int,
    v[7] as int,
    v[8] as int,
    v[9] as int,
  );
  static List<BandLogRecord> decode(List<int> value, int length) {
    if ((length != 16 && length != 20) ||
        value.isEmpty ||
        value.length % length != 0) {
      throw const FormatException('Invalid log packet');
    }
    final b = BandProtocol.bytes(value);
    return [
      for (var o = 0; o < value.length; o += length)
        BandLogRecord(
          b.getUint32(o, Endian.little),
          b.getUint32(o + 4, Endian.little),
          b.getUint16(o + 8, Endian.little),
          b.getUint16(o + 10, Endian.little),
          b.getUint8(o + 12),
          b.getUint8(o + 13),
          b.getUint8(o + 14) * 10,
          b.getUint8(o + 15),
          length == 20 ? b.getUint8(o + 16) : 0,
          length == 20 ? b.getUint8(o + 17) : 0,
        ),
    ];
  }
}
