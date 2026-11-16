import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BandPermissions {
  const BandPermissions();

  static List<Permission> forAndroidSdk(int sdk) => sdk >= 31
      ? [Permission.bluetoothScan, Permission.bluetoothConnect]
      : [Permission.locationWhenInUse];

  Future<List<Permission>> _required() async {
    if (Platform.isAndroid) {
      return forAndroidSdk(
        (await DeviceInfoPlugin().androidInfo).version.sdkInt,
      );
    }
    if (Platform.isIOS) return [Permission.bluetooth];
    return [];
  }

  Future<PermissionStatus> status({bool request = false}) async {
    try {
      final permissions = await _required();
      if (permissions.isEmpty) return PermissionStatus.denied;
      final statuses = <PermissionStatus>[];
      for (final permission in permissions) {
        statuses.add(
          request ? await permission.request() : await permission.status,
        );
      }
      if (statuses.every((status) => status.isGranted)) {
        return PermissionStatus.granted;
      }
      if (statuses.any(
        (status) => status.isPermanentlyDenied || status.isRestricted,
      )) {
        return PermissionStatus.permanentlyDenied;
      }
      return PermissionStatus.denied;
    } catch (_) {
      return PermissionStatus.denied;
    }
  }

  Future<bool> locationServicesRequired() async {
    if (!Platform.isAndroid) return false;
    try {
      return (await DeviceInfoPlugin().androidInfo).version.sdkInt < 31;
    } catch (_) {
      return true;
    }
  }
}
