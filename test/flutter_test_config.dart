import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:umbra/core/ble/band_database.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  final directory = await Directory.systemTemp.createTemp('umbra-db-test-');
  await databaseFactory.setDatabasesPath(directory.path);
  setUp(() async {
    await BandDatabase.close();
    await databaseFactory.deleteDatabase(
      path.join(directory.path, 'umbra_band.db'),
    );
    await BandDatabase().initialize();
  });
  tearDown(() async => BandDatabase.close());
  await testMain();
}
