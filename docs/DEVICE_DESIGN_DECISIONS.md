# Waveshare device — design decisions log

Every user-facing decision for the standalone cycling computer (Waveshare ESP32-S3-Touch-LCD-1.28-B) is recorded here with
its date and source, so approved screens are not redesigned by accident. Proposals awaiting Rashed are marked PENDING.

## Standing direction (2026-10-23, from Rashed)
- Build the Waveshare as a complete standalone cycling computer FIRST; companion iOS/Android apps only after it is
  operational, tested and reliable. Firmware is organised so future apps can sync (BLE sync, ride export, shared profile
  structures, firmware updates, optional cloud) — architecture only for now.
- All setup and essential ride functions work on the device itself; no phone required for onboarding.
- Rashed approves every major screen: options with visuals → his choice → implementation → rendered preview → changes.
- First milestone: real power and cadence from the XDS meter on the Waveshare without the Nokia, HR strap or phone.
- Never flash without his approval. Never show simulated values as real; missing sensors show NO DATA / NO STRAP.
- Coaching reacts to real sensor data with an identifiable reason for every instruction; scheduled workout phases are kept
  separate from performance-based cues; works without HR; runs offline.
- Carry over from the Android app: starting FTP = weight × W/kg by experience (labelled as an estimate), automatic FTP
  learning from qualifying sustained efforts, meter verification separate from FTP, per-rider data isolation, no sample
  riders in production.

## Round 1 (proposed 2026-10-23) — design/device/device_design_r1.html
| # | Decision | Options | Recommended | Status |
|---|---|---|---|---|
| 0 | Onboarding flow | Welcome → Name → Age → Weight → Experience → Main goal → Power meter → (HR strap) → (Wi-Fi) → Ready | as listed | **APPROVED** 2026-10-23 with: power-meter pairing skippable (setup never blocks); HR and Wi-Fi optional; wheels for age/weight, letter ring for name; initial FTP labelled a PROVISIONAL STARTING ASSUMPTION, never measured |
| 1 | Navigation | A ride-pages carousel + pull-down panel, hold-to-confirm Pause/End · B circular hub · C watch list | A | **APPROVED A** 2026-10-23 |
| 2 | Number entry | A spinning wheel · B edge dial · C − / + buttons | A | **APPROVED A** 2026-10-23 |
| 3 | Name entry | A letter groups around the ring · B paged keyboard · C phone-assisted (extra only) | A | **APPROVED A** 2026-10-23 (letter ring only; no phone option) |
| 4 | Ride dashboard | A Power Focus · B three gauges · C minimal + swipe | A | **APPROVED A** 2026-10-23 (built first) |
| 5 | Height in onboarding | ask (optional) · leave to Settings | leave to Settings | **APPROVED: Settings only** 2026-10-23 |

## Sequencing (2026-10-23, Rashed)
Full onboarding implementation starts only after the display, touchscreen and XDS BLE connection have been physically tested on the device with the Phase A diagnostic build. Order: Windows recognises the board → confirm COM port and hardware identity → back up factory firmware → Rashed approves → flash diagnostic.

## Round 2 (2026-10-23, firmware 0.2.0) — implemented from the approved designs, rendered by the real firmware
Previews: test/sim (`make run` then `python3 sheet.py out`), every screen checked automatically against the round glass.
| # | Decision | Options | Recommended | Status |
|---|---|---|---|---|
| 6 | Main ride page | A Power Focus (approved round 1) · B Split (watts top, cadence | HR below) · C Coach First (instruction + colour ring) | A | **PENDING** — A is the default; B and C selectable in Settings > Ride screen so the choice never blocks testing |
| 7 | Ride controls | pull-down panel (swipe down or tap the top handle): hold 1 s PAUSE, tap RESUME, hold 2 s END | as built | implements approved navigation A |
| 8 | Results | SAVE (tap) / discard (hold the bin 1.5 s) | as built | new |
| 9 | Home | START RIDE + Sensors / History / Settings, status line (meter, HR, battery), FTP with PROVISIONAL label | as built | new |
| 10 | Demo mode | orange DEMO badge on every screen, separate demo history, never changes FTP, OFF after every restart | as built | new |
