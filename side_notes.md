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
| Night Mode (active while drinking) | **35 min** | 20 / 30 / 45 / 60 min |
| Daily Mode (passive all-day hydration) | **90 min** | 20 / 30 / 45 / 60 min |

Note: an earlier draft in the client doc said Night default 40 min with
20/30/40/60 options, a later "few key reminders" follow-up from the same
client explicitly updated this to **35 min default, 20/30/45/60 options**.
Treat the later message as authoritative; the 40/40 numbers are superseded.

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
  silently assume it's resolved. Worth confirming with the user before deep
  BLE work, since the BLE integration approach (flutter_blue_plus vs.
  CoreBluetooth directly) and the "Apple Watch companion" deliverable both
  hinge on this.
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

## Timeline (for context, not a hard deadline the app has to hit)

Client's stated project start: 3 June 2026, 3-week duration. Contractor's
feasibility report allocates 60 hours / 3 weeks to app development
specifically (BLE layer gets the largest single slice at 14 hours). Milestone
4 in the client's own doc is "prototype arrives in New York and functions
correctly", the hardware side has its own independent timeline; nothing here
implies this Flutter app is on the same 3-week clock unless the user says so.
