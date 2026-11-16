# Android hardware integration validation

Build: Umbra 1.0.0 (4). Firmware contract: 1.1.0 from the user-supplied
`E:/Smart_hydration_Band.zip`. The contract is retained in
[firmware-ble-interface.md](firmware-ble-interface.md). Firmware source was not changed.

## Verified in this workspace

- Flutter analyzer: no issues.
- Unit and widget tests: 16 passed. These cover byte encoding, zero/stale HR,
  hardware-only session start, physical mode notifications, rejected writes,
  read-modify-write interval changes, incomplete log recovery, persistence,
  deduplication, and morning notification planning and cancellation.
- Android 16/API 36 emulator integration test: passed. With no band connected,
  the application has no generated readings, no seeded history, and no enabled
  session or hardware commands. Onboarding and navigation remain usable.
- Test protocol peers live only under `test/support/`; the release target is
  `lib/main.dart` and does not include them.

## Physical band checks still required

Connect a band advertising Umbra and confirm the firmware version on Band Detail.
Compare the displayed mode and intervals with the band, then switch modes using
both the physical button and the app. Change one interval and reconnect to check
that the other interval is preserved and the new value is read back.

Wear and remove the band to check HR availability and the three-second expiry.
Use Test band vibration to check the physical double tap; the firmware ignores
commands less than two seconds apart. Request a SpO2 measurement with the wrist
still and check its status, quality and timestamp rather than expecting a
continuous oxygen reading.

Leave the phone disconnected while the band records a night, reconnect, and check
that the log sync recovers the session once with no duplicate rows after another
sync. Check the single next-morning notification on the intended Android phone.
Android inexact alarms may be delayed by the OS; force-stopping an app can prevent
scheduled delivery until it is opened again.

## Firmware delivery notes

The supplied `Firmware/include/app_config.h` has `APP_SPO2_BENCH_MODE` set to 1.
The firmware documentation says to set it to 0 for delivery. Bench mode performs
frequent attempts and uses more battery. SpO2 calibration is also marked
incomplete in the firmware; the application presents these values as wellness
estimates, without manufacturing replacement readings.

The firmware exposes neither HRV nor a reminder countdown/count. Those displays
were removed. Untimed hardware log records are stored without invented dates.
The app reads the band's actual interval values, including its current 35-minute
Night factory default, rather than overwriting it with the former app default.

## Packaging

Final artifact: `build/app/outputs/flutter-apk/umbra-hardware-build4.apk`.
Signature verified; version code 4; Android minimum API 24, target API 36;
ARM32, ARM64 and x86-64 libraries included. The final release artifact was
installed and cold-launched on the emulator with no AndroidRuntime/Flutter
error log entries for its process. Its onboarding screenshot was reviewed.

SHA-256: `38DA2E472D04998F133FF8ADDC4347341C1AF00EB4EBE2273006D7BE668E66FA`.

The APK uses the repository's existing debug signing identity for sideload testing.
Production distribution signing and physical iOS regression testing are outside
this Android validation run.
