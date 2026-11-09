# B2 — Stage 1 hands-on hardware validation (9 Nov 2026, 21:55–22:46 Dubai)

Approval: B2 only (21:53). No flash write, erase, rebuild, bootloader/partition/OTA change. Installed firmware unchanged
(faa2828f…). B3 not approved, not run. Watch powered by USB only (no battery fitted).
Tooling: `b2_stage1_tests.py` (PC `b2_tests.py`) — serial only, never runs esptool; restarts are normal EN resets with boot
confirmation; listening opens COM4 with DTR/RTS released. Serial test hooks are the Stage 1 single-character commands.
Evidence: PC private log `b2_log.txt` (serial lines + owner answers summarised here).

| ID | Test | Result | Evidence |
|---|---|---|---|
| V2-1 | Screen stays on (5 min) | **PASS** | 300 s, 0 restarts, perf line every 30 s, heap 187,880 B stable; owner: on the whole time |
| V2-2 | Rendering and navigation | **PASS** | owner: face ↔ menu clean and quick for every press. Serial log not captured (IDLE focus loss in the test harness) |
| V2-3 | Upper button | **PASS** | owner pressed ≈10×; log: 10 × `key1` (no double counts); every press switched the screen |
| V2-4 | Lower button | **PASS** | log: 4 × `key2: back`, 3 × `key1` in the expected order; nothing on the face, back from the menu. Owner also pressed the third (boot, IO0) button once by mistake: no event, no effect |
| V2-5 | Touch taps | **PASS** | tap on a menu item started a ride: `ride started (simulated)`; owner: taps reacted normally. Taps on areas without an action leave no log trace |
| V2-6 | Touch swipes | **PASS** | log: `swipe U`, `swipe D`, `swipe R`, `swipe L` — all four directions, in the order performed |
| V2-7 | Cockpit + simulated metrics | **PASS** | hooks b/p/p/s×4; log: `key2: back`, pause and resume each `command sent → command confirmed`; owner: values update, pause/resume shown, missing sensors shown as missing (not zero) |
| V2-8 | Arabic interface | **PASS** | owner: Arabic, right-to-left, letters complete and joined, nothing cut off (cockpit, face, menu) |
| V2-9 | Text density | **PASS** | focused/standard × default/large text in Arabic and English, menu and cockpit; owner: everything readable, no overlap/cut-off |
| V2-10 | Normal restart ×3 | **PASS** | 3/3 `BOOT CONFIRMED` (one start, Cyclift banner, first frame 565 ms); owner: Cyclift face shown |
| V2-11 | USB reconnection ×3 | **PASS** | owner: Cyclift back after each of 3 reconnections; PC check afterwards: answered without reset |
| V2-12 | Serial logs and stability (10 min, ride running) | **PASS** | 600 s, 20 perf reports, 0 restarts, heap free constant 187,728 B (no leak), avg render 0.9–4.2 ms, max frame 367 ms |
| V2-13 | End state | **PASS** | 22:45:53 Cyclift answered without reset (not in download mode); owner: screen on, simulated ride ("power meter demo") still showing |

## Findings
1. **Touch works under Cyclift (confirmed).** Taps and all four swipes registered. The touch hardware is functional; the
   earlier "no reaction" in the factory Touch app is not explained by hardware. Status of the factory-app result: unconfirmed
   (possible causes in the factory firmware's touch configuration or its contact-flag check; not investigated further — not
   needed for Cyclift). Touch issue → closed for Stage 1; broader touch accuracy/coverage not measured.
2. **Cockpit and Arabic rendering cost (firmware, supported).** Face/menu frames ≈0.4 ms average, max ≈25 ms. Cockpit average
   1.5–4 ms with occasional frames of 0.36–0.38 s; Arabic average 9–11 ms with max ≈0.38 s. The 0.37 s stalls coincide with
   screen rebuilds (perf `rebuilds` > 0). Owner saw no visible problem, but a 0.37 s freeze during a ride is too long for live
   metrics. Likely cause: full widget-tree rebuild on state changes instead of in-place updates (not yet confirmed by profiling).
3. **Third physical button = ESP32 boot button (IO0) (hardware, confirmed by owner action).** No function in Stage 1; harmless
   while running. Holding it during a reset would start download mode — keep it untouched during restarts.
4. **No battery fitted (hardware).** Watch runs only on USB. Battery level, charging, unplugged operation, sleep/wake and
   on-wrist use cannot be tested on this unit until a battery is fitted.
5. `E (651) esp_core_dump_flash: No core dump partition found!` at every boot (firmware configuration, confirmed, harmless):
   core dump is enabled but the partition table has no core-dump partition.
6. Test-harness issue (not the watch): IDLE focus loss twice prevented a recording (V2-2 log, first V2-4 attempt); results were
   re-checked by the owner and V2-4 was repeated with recording.

## Classification
| Issue | Firmware | Hardware | Unconfirmed |
|---|---|---|---|
| Cockpit / Arabic 0.37 s frame stalls | ✓ (supported) | | cause not profiled |
| Core-dump error line at boot | ✓ (confirmed) | | |
| Third (boot) button has no function / reset risk | | ✓ | |
| No battery | | ✓ | |
| Factory Touch app showed no reaction | | | ✓ (touch hardware itself works) |
| Board revision V1.0/V1.1 (interrupt routing only) | | | ✓ |
| Build timestamps make rebuilds differ (36 bytes) | ✓ (confirmed) | | |

## Recommended fixes (priority order, all need separate approval)
1. Remove the cockpit/Arabic frame stalls: update cockpit values in place, rebuild only on layout changes; add a CI render-time
   budget (e.g. max frame < 50 ms in the host renderer) — firmware.
2. Fit a battery (owner hardware) and repeat the power-related checks; required before wearable/standby work.
3. Reproducible builds (fixed `__DATE__`/`__TIME__`, CI double build) before the next firmware candidate.
4. Disable core dump or add a core-dump partition in the next layout revision (cosmetic, avoids a misleading error line).
5. Determine the board revision (needed before motion/RTC interrupt features).
6. Harness: run long recordings in a dedicated window so a focus change cannot block a test.

## Readiness
Stage 1 is validated on this physical watch: 13/13 tests PASS, including touch, Arabic, restarts, USB reconnection and a 10-minute
stability run without restart or memory growth. Ready for the owner's review. Recommended before the next development stage: fix 1
(frame stalls) in the next firmware candidate. Stage 2b and new features are not started (owner review required).
