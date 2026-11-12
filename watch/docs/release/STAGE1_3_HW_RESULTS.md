# Stage 1.3 RC1 — hardware results (11 Nov 2026) — INTERIM: validation stopped on a defect

Owner approval 15:41 (install of 4ea0ea90… + non-destructive acceptance). Serial log: `evidence/rc1_hw_log_20261111.txt`.

## Verdict
**HARDWARE VALIDATION NOT PASSED — stopped and reported (owner rule: stop on failure before further physical changes).**
RC1 remains installed and running. No rollback, no other writes.

## Installation (15:50–15:56) — PASSED, all 12 conditions
s13_pre: firmware fingerprint, chip, backup, Stage 1.1 installed, whole-flash read, layout and app1 region all PASS.
s13_write: one write 0x400000 (1,196,032 B), byte-verified, boot "Stage 1.3" confirmed. s13_post: whole-flash diff
292 sectors = exactly the write span; nothing outside app1 changed (bootloader, table, OTA, factory app, settings, files
unchanged). Watch left running normally.

## Automated serial diagnostics (15:57–16:34) — passed
| Measurement | RC1 | Stage 1.1 (10 Nov) |
|---|---|---|
| Reported free heap / min | 183,484 / 155,208 B | 121,028 / 94,500 B |
| Usable 8-bit heap / min / largest block | 125,728 / 97,496 / 53,236 B | ≈113.5 KB (derived) / — / — |
| PSRAM free | 2,095,104 B (1,978,364 in ride: ring image) | — |
| Stack headroom (min) | loopTask 4,228 B of 8,192; IDLE0/1 568/572 B; others ≥ 1,500 B | — |
| LVGL pool used / sampled peak | 4,504–5,500 / 8,952 B of 65,536 | — |
| Screen transitions (rebuild) EN | p50 230 ms, max 318 ms | 213–362 ms |
| Screen transitions AR | p50 254 ms, max 342 ms | — |
| Ride 1 Hz update EN / AR | p50 91 / 88 ms, max 139 / 132 ms; 30-min p50 85, p99 130 | p50 71, max 112 / 105 ms |
| Ride start rebuild | max 496 ms | — |
| Clock | invalid at start (no battery) → set from PC → counts correctly; kept time through 2 restarts | `--:--` (no time source) |
| 30-min ride soak | 0 unexpected restarts; heap constant (122,988 B 8-bit); LVGL use flat | 10 min, 0 restarts |
| Normal restarts | 2/2 confirmed "Stage 1.3 RC1", first frame 576 ms | — |

Finding P1: unexplained full-screen rebuild about once a minute while idle or riding (≈ 206–350 ms each), with no input.
The structure key has no time-varying field in the computer model (30-min simulation: none). Device-only candidates:
clock-chip read failing for one 10 s cycle (valid flag flips) or the charge-status pin toggling (no battery fitted). Not yet
proven which.

## Guided owner session
Part 1 (English, no demo data): Today/Week PASS, Quick Settings PASS, menu PASS, lock PASS, responsiveness PASS.
- Clock ISSUE: face shows `--:--` although the clock is valid. **Cause found (design defect D6):** the face shows the time
  only when `synced && clock.valid`; RC1 starts "not synced" (approved honest default), so the time is hidden until demo
  data is on. Fix proposed: show the time whenever the clock is valid; keep "NOT SYNCED" for data. Owner decision.
- Widgets show dashes — expected (data needs sensor / iPhone); "Not in this release" pages — approved decision 2.
Part 2 (demo data, Bike ride): clock PASS, Today/Week PASS, Coach PASS; Ride ISSUE, Lap ISSUE, smoothness ISSUE (details to
be recorded); after pressing Key 2 the watch showed the clock then `--:--`.
- **Unexpected restart (defect D7):** the serial status at 19:46 shows the frame counters restarted ≈ 3 min earlier
  (≈ 19:43, when the owner pressed Key 2) — a restart clears the demo data, which explains the `--:--`. Reset reason not
  captured (recording was not running at that moment). Computer reproduction (1,200 rides × 400 random Key 2 / Key 1 /
  tap / swipe inputs, EN/AR, all modes, AddressSanitizer + UBSan): no fault. Candidates: device-only code, power dip
  (no battery), or a press of the reset button.

Recording gap: the serial listeners for Parts 1 and 2 had ended before the owner started each part; touch logs and frame
times for those parts were not captured.

## Not done
Part 3 (Arabic, Large Text on the watch); end-of-session report. Paused by the stop rule.

## Proposed next steps (need approval)
1. Reproduction session (non-destructive): continuous recording, owner repeats ride + Key 2 twice; the ROM prints the
   reset reason (brown-out / watchdog / panic / power-on).
2. Offline RC2 fixes: D6 time display; P1 debounce (clock invalid only after 3 failed reads; charging state ignored when no
   battery voltage); D7 per reproduction result. New file name and fingerprint; separate install approval.

## Restart recording, 12 Nov 11:11–12:59 (read-only monitor; RC1 unchanged)
- Continuous recording 11:11:20 → 12:59 (`evidence/rc1_restart_recording_20261112.txt`, extract). The owner's restart test
  (ride, Key 2 laps, Key 1) ran 11:15–11:17 without a restart.
- **Three chip starts were recorded afterwards, at 11:17:42.146, 11:17:42.661 (0.5 s later) and 11:17:54.694**, each
  `rst:0x1 (POWERON_RESET)` followed by a normal Cyclift start. The last inputs before them: Key 2 at 11:17:33–37 (5 s
  earlier), swipes at 11:17:47–52. No panic, watchdog or brown-out text; no serial port errors.
- **Two more starts at 16:36:13.6 and 16:36:14.1 (0.5 s apart, again POWERON_RESET)**, with no button or touch event in
  the minutes before; normal Cyclift start after. Same double pattern as 11:17:42. Not yet explained (owner asked whether
  he handled the watch or the cable at that moment).
- On the ESP32 the ROM reports a press of the reset line (R1, the right upper button) and a supply power-up both as
  POWERON_RESET; a firmware crash or watchdog shows a different code and a crash dump. Two starts 0.5 s apart look like a
  bouncing contact (button or connector), not software.
- No further start until 12:59 (the latest copy of the log; the monitor keeps recording until ~19:11). The 2-hour idle recording of 11 Nov (20:56–22:56) also had none.
- Assessment: D7 is most likely the reset button pressed while handling the watch (pinch with L1 opposite) or a brief
  power interruption at the connector — **not proven**. The G1 / G11 physical check (owner instructions sent 12 Nov ~13:00)
  and the Stage 1.4 start log (reset reason, start count, every decoded key) are the next evidence. Per the owner's
  instruction, no further reproduction cycles without new evidence.
