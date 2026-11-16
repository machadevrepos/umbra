# Umbra, Side Notes

Working reference distilled from the client brief and feasibility report in
`Project AI-Powered Smart Hydration & Wellness Wristband (Brad)/`. Read this
alongside `CLAUDE.md` (design system) before building screens, this file
covers *what the product is and does*; `CLAUDE.md` covers *how it should
look and feel*. Don't duplicate design rules here; don't invent product
features here either, if it's not in the source docs or confirmed by the
user, it's an open question below, not a default.

## What Umbra is

A passive behavior-change wristband that reminds people to drink water.
Core loop: **band buzzes → user drinks water → that's it.** No logging, no
tapping, no setup. Pitched as "a Whoop for nightlife", not preachy,
not anti-drinking, just a smart nudge so you feel better the next morning.

**Non-negotiable:** the band works completely standalone, with zero app
pairing or setup out of the box. The app *enhances* the experience, live
data, history, adjusting intervals, but the haptic reminder itself must
never depend on the app being open or even installed.

Client: Brad. Contractor for hardware/firmware/feasibility: M. Bilal Javid
(the two PDFs in the project folder, one is the client's own spec email,
the other is the hardware contractor's feasibility report for the physical
band/PCB/enclosure, not for the app we're building here).

## Two modes

| Mode | Default interval | Adjustable options |
|---|---|---|
| Night Mode (active while drinking) | **Read from band (firmware default 35 min)** | 20 / 30 / 45 / 60 min |
| Daily Mode (passive all-day hydration) | **90 min** | 20 / 30 / 45 / 60 min |

Note: the client's original doc said Night default 40 min with 20/30/40/60
options; a later "few key reminders" follow-up changed this to 35 min
default with 20/30/45/60 options; then Brad's build-107 TestFlight review
(2026-09-07) asked for the default back to 40 min for the beta, keeping
the 20/30/45/60 options from the second message. This was the beta
combination — 40 min default, 20/30/45/60 options — The supplied firmware now defaults to 35 minutes; the app reads the band rather than overriding it.

Haptic pattern: **double tap, two short, firm pulses**, strong enough to
feel clearly in a loud bar or festival environment. This is a firmware/
hardware detail, but it matters for any in-app haptic preview or reminder
simulation the app might offer.

## Sensors, v1 scope

HR (essential), HRV (derived from HR, no new sensor), full PPG waveform
(firmware only), respiration rate (derived from HR), skin temperature,
SpO2, accelerometer (movement context, steps, sleep detection, logged
passively, **not featured prominently in v1 UI**).

**GSR is explicitly dropped for v1**, client called it out twice ("too
noisy, will add in v2" / "prob don't need GSR"). The hardware contractor's
feasibility report still includes a full GSR subsystem (sensor, PCB
section, electrodes, example BLE payload with a `gsr` field), that's the
contractor's own scope-of-work boilerplate and conflicts with the client's
direct instruction. **Follow the client, not the feasibility report, on
this:** don't design any v1 app screen around GSR/sweat data.

## App, "ruthlessly simple" (client's own words)

- Mode selector, Daily or Night
- Interval adjustment, 20 / 30 / 45 / 60 minutes
- Live HR display, with HR zone (resting / elevated / high) shown via
  color coding, but per `CLAUDE.md`, color alone can't be the only signal,
  pair it with a label/icon too
- Session tracking, start/end a night out (or a daily-mode session)
- Session history, past sessions with biometric averages
- Single morning check-in notification at 9am, "How do you feel 1,10?",
  correlated against the previous session's data. **Just one notification.**
  Don't add more prompts than this; the client was specific about "single."
- Battery level, BLE connection status
- Steps and sleep logged passively in background, data exists, stays out
  of the primary UI in v1
- Insights, over time, surface what patterns precede the best/worst
  mornings (this is the one screen that leans slightly more "analytical,"
  keep it in the same restrained visual language, not a dashboard)
- Apple Watch companion: mirrors the active session, shows HR zone, fires
  haptic reminders on-wrist, syncs session data back to the phone

App aesthetic per the client, verbatim: **"dark background, premium feel,
clean and minimal. Think Oura app meets nightlife. Not medical looking."**
This is exactly what `CLAUDE.md`'s design system already encodes (dark-first,
one gold accent, generous negative space), no translation needed, the
constitution already fits the brief.

## Explicitly out of scope (client said so directly)

- Custom PCB (breadboard/module prototype is fine for v1)
- Injection-molded enclosure (3D printed is fine)
- App Store submission
- Backend/server infrastructure
- GSR (see above)

## BLE / firmware context (not what this codebase builds, but shapes the app's data layer)

- MCU: ESP32 or equivalent, BLE-capable
- Band has an **onboard fallback**: if BLE drops, it keeps firing reminders
  on the default interval independently, the app's BLE layer should be
  built assuming the band doesn't need it to function, only to enhance
 , reconnection handling should be graceful, never blocking core reminder
  behavior
- Example telemetry shape from the feasibility report (drop the `gsr` key
  per the v1 scope decision above):
  ```json
  { "device_id": "HYDRO-WR-001", "heart_rate": 92, "spo2": 97, "battery": 78, "session_active": true }
  ```
- Example command shape: `{ "command": "trigger_haptic", "pattern": "hydration_reminder", "duration": 3 }`

## Open questions / things to flag rather than assume

- **Platform mismatch:** the client's brief explicitly asks for a native
  **SwiftUI iOS app + WatchOS companion**, built from scratch in Xcode, with
  a documented Swift BLE manager class. This repository is a **Flutter**
  project. If that's a deliberate change of direction (e.g. cross-platform
  now matters more than matching the brief literally), fine, but don't
  silently assume it's resolved. The BLE integration approach is decided
  for the Flutter side now (see "BLE integration, decided" below), but the
  "Apple Watch companion" deliverable specifically still hinges on this,
  a Watch app is native-only regardless of what the phone app is built in.
- **Dubai/bilingual scope vs. the brief:** `CLAUDE.md` frames Umbra as a
  Dubai launch with mandatory Arabic/English bilingual support from day one.
  Brad's brief never mentions localization and describes delivery to New
  York, plausibly the NY prototype is for the client demo/investor round
  and Dubai is the actual go-to-market, but that's inference, not stated
  fact. Don't let the nightlife/alcohol framing in the brief clash with
  UAE cultural norms without checking, worth a direct question if it
  becomes relevant to copy or feature framing.
- Interval option sets differ slightly across the two client messages (see
  Modes table above), resolved in favor of the later message, but flagging
  since the source docs disagree.
- No data model, state management choice, or folder structure is decided
  yet, `CLAUDE.md` says to document that decision here once made. Nothing
  to record yet; `lib/` is still the default `flutter create` scaffold.

## Hardware integration (current firmware)

The user supplied `E:/Smart_hydration_Band.zip`. The source contract is copied
verbatim to `docs/firmware-ble-interface.md` and checked against
`Firmware/src/ble_service.c` and `Firmware/include/app_config.h`.
The firmware source itself is not modified by this app change.

The app uses `flutter_reactive_ble` and the firmware's standard Heart Rate,
Battery, Device Information, and custom Umbra binary GATT characteristics.
The advertised name prefix is `umbra`. There is no bonding. The old UART JSON
reader and its provisional sensor fields have been removed.

- Time is written on each connection and on returning to the app.
- Mode is read/subscribed and confirmed by hardware before changing the UI.
  The physical button can change the app's mode and session state too.
- Intervals are read from the band. Changing one reads both, preserves the
  other, writes the two uint16 little-endian values, then reads them back.
  The current firmware defaults to Daily 90 and Night 35 minutes. These
  device values supersede the former beta app default of 40 in the UI.
- Heart rate comes from 0x2A37. Zero or about 3 seconds without a notification
  becomes no reading immediately. There is no simulated fallback.
- Steps come from the band's uint32 since-power-on counter and appear on Home
  and Band Detail. Each received counter is saved with its device ID and receipt
  time in SQLite (`umbra_band.db`). Daily and Night log records, including step
  deltas and their validity flags, are saved in the same database. Log records
  and their sync cursor commit in one transaction; old preference logs migrate
  on startup. Session details show summed valid log steps, or observed live
  counter deltas until a hardware sync replaces them. Resets/disconnections
  leave uncertain session totals unavailable rather than inventing steps.
- Connection-time reads cannot overwrite newer notifications or update a
  forgotten/disconnected band. Sudden battery drops over 20 percentage points
  within a minute require a fresh Battery Level read before changing the display.
  A confirmed zero remains valid; failed verification keeps the last confirmed
  value with an explanation. Battery is also refreshed every 30 seconds.
- SpO2 is a spot check with status, quality, and a last-valid timestamp.
  The app can request measurement with byte 1 and displays failed-attempt
  reasons while retaining the last reading with its age. Session averages
  count new measurements rather than every repeated status notification.
- The vibration test writes byte 1 to the Haptic characteristic. It never
  substitutes a phone vibration for a successful band command.
- History sync subscribes before requesting records, validates sequence
  continuity, supports 16/20-byte records, persists raw records and the next
  cursor together after the end marker, and deduplicates by device/sequence.
  Untimed boot records remain stored without invented calendar dates.
- Night history is reconstructed from consecutive Night records, with ratings
  preserved across repeated syncs. A connected mode transition can also save
  an observed session; later hardware logs replace overlapping observations.
- Offline users can view saved history and settings, but cannot start a new
  session, change band mode/intervals, or send commands.

HRV, motion classification, reminder counts, and the next-reminder timestamp
are absent from this firmware's public contract. The app does not invent them
or show a phone-generated countdown. The band owns autonomous reminders.
There is no seeded production history and no production demo mode.

Morning check-ins are one-off notifications targeted to local 9am following
an actual completed hardware session. They open the matching rating screen,
are cancelled after rating or disabling, and do not re-prompt a missed night.
Android uses inexact scheduling without special alarm access, so the OS can
delay delivery. Android reboot/update receivers restore pending schedules.
History, ratings, actual-session observations, and preferences persist locally.

Android permissions use Nearby Devices on Android 12+; older Android needs
location permission and enabled Location services for scans. Permission
failure leaves the app usable without pretending a band is connected.

Firmware handover note: `APP_SPO2_BENCH_MODE` is 1 in the supplied source.
The firmware documentation says to set it to 0 for delivery; while enabled,
SpO2 attempts run much more often and consume more battery. Calibration is
also explicitly marked incomplete. This app does not silently change firmware
or claim medical accuracy.

Apple Watch, Arabic localization, quiet-hours editing, and production signing
remain separate work. Hardware-in-the-loop validation requires a physical band.

## Timeline (for context, not a hard deadline the app has to hit)

Client's stated project start: 3 June 2026, 3-week duration. Contractor's
feasibility report allocates 60 hours / 3 weeks to app development
specifically (BLE layer gets the largest single slice at 14 hours). Milestone
4 in the client's own doc is "prototype arrives in New York and functions
correctly", the hardware side has its own independent timeline; nothing here
implies this Flutter app is on the same 3-week clock unless the user says so.
