# iPhone BLE validation

## Changes awaiting physical validation

The app now waits for native notification setup acknowledgements before reading
configuration or requesting history. Incoming values are listened to before
enabling notifications so immediate packets are retained. GATT reads, writes,
and notification setup are serialized with bounded operation timeouts.
Subscription failures cannot be overwritten by successful initialization.

On iOS, flutter_reactive_ble 5.4.2 reports connected after its initial service
discovery; the app reuses those discovered services instead of repeating it.
Android retains explicit service discovery. Standard 16-bit UUIDs are matched
against their expanded forms, retaining native service/characteristic instance IDs.

The checked-in CocoaPods configuration enables PERMISSION_BLUETOOTH=1 for
permission_handler_apple in every build configuration. Info.plist already has
NSBluetoothAlwaysUsageDescription and bluetooth-central background mode.

These changes address setup races and a permission configuration gap. The exact
cause of the reported iPhone failure remains unconfirmed without device logs.

## Build on macOS

From the project root:

```sh
flutter pub get
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

For a physical device, use the project's existing signing configuration with
`flutter run --release -d <iphone-device-id>` or create a new signed TestFlight
build through the existing deployment workflow. An existing installed build
does not receive these changes until rebuilt. Do not remove app data or saved
history to test the update.

## Physical checks

1. Disconnect Android from the band first: firmware supports one phone at a time.
2. Allow Bluetooth for Umbra in iPhone Settings and connect in the app.
3. Confirm battery, steps, firmware version, and actual mode load in Band Detail.
4. Wear the band and confirm HR arrives, then remove it and confirm expiry.
5. Test band vibration; switch Daily/Night from the app and physical button.
6. Change one interval, reconnect, and confirm both intervals retain their values.
7. Request SpO2, keep still, and check status and eventual measurement.
8. Record a night while disconnected; reconnect and confirm history imports once.
9. Background and resume the app; toggle Bluetooth off/on and verify recovery.
10. Repeat battery, HR, vibration, interval, and history checks on Android.

If a step fails, record iPhone model, iOS version, app build, firmware version,
the exact Band Detail error, and the device-console entry beginning
`Band setup failed`. Setup errors now identify the operation that failed;
the console includes the underlying exception and stack trace.

## Local verification

Windows unit/widget tests cover native notification acknowledgement delays,
immediate data, rejected subscriptions, 16-bit UUID resolution, operation
serialization, and controller readiness, alongside existing hardware/session
tests. These tests do not establish physical iPhone interoperability or iOS
build success. macOS compilation and the physical checks above remain required.
