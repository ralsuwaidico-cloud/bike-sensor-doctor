# Stage 1.3 RC2 — offline candidate (11 Nov 2026) — NOT INSTALLED

Owner approval 20:51: offline RC2 work + one read-only restart investigation. RC1 (4ea0ea90…) stays installed until a
replacement is approved separately.

## Candidate
| Item | Value |
|---|---|
| File | `cyclift-stage1.3-rc2-v3poc-T-Watch-2021-V1_1.bin` |
| SHA-256 | `82500ce2a2531271573489c9080d7372e0ee97c330e44cbb85f2f3a2040da461` |
| Size | 1,197,184 B (RC1 1,194,112); header DIO / 40 MHz / 8 MB |
| Source | commit 6c07f69, CI 43064696858 (all 6 jobs green) |
| Reproducible | two clean builds + published file identical (82500ce2…) |
| Pins | `releases/stage1.3-rc2.sha256`, `cy_update_rc2.py`, `cy_recover_b.py` |
| Install plan | one write 0x400000–0x524FFF (1,200,128 B), base = installed RC1; rollback `r2_rollback` → RC1, then `s13_rollback` → Stage 1.1 |

## Changes from RC1
1. **Clock (owner decision 20:51, defect D6):** time and date follow the clock chip alone. Valid → shown; invalid → `--:--`
   and no date; iPhone link, sync state and demo data no longer affect it. "NOT SYNCED" stays for iPhone data only.
2. **Missed clock reads (ClockKeeper):** a read the chip does not answer keeps the last confirmed time, advanced by the
   processor clock, for up to 3 reads (30 s); a 4th miss in a row → `--:--` until a read succeeds. A chip reporting lost
   time (VL bit, e.g. after power loss) → `--:--` at once, never stale time. Every miss is printed on serial.
3. **Charge-status pin debounce:** the shown charging state changes only after 3 equal samples (30 s). Raw changes are
   counted and printed. A real plug/unplug still shows within 30 s.
4. **Diagnostics (serial only):** reset reason (power-on / brown-out / panic / watchdog / software / external pin) and
   start count since power-on at boot; uptime and boot number in every `perf:` line; the cause of every full-screen
   rebuild (`rebuild: charging`, `rebuild: clock valid`, `rebuild: screen` …).
5. Banner "Stage 1.3 RC2". No other behaviour change; no fix for the unexplained restart (none proven).

## Tests (computer / CI 43064696858)
| Suite | Result |
|---|---|
| Model | 1,720 checks, 0 failed |
| Navigation oracle + 200,000-input soak | 539 checks (was 353), 0 failed |
| **Lap regression** (new) | EN/AR × Wrist/Bike/Gym × start from Today or Menu; owner sequence (Key 2 twice 0.5 s apart, 3 laps), single press expiry, 2.6 s gap, 4 bounce-fast presses, Key 2 while paused: 36 laps, 0 failed |
| Lap stress under AddressSanitizer + UBSan (computer) | 1,200 rides × 400 random Key 2 / Key 1 / tap / swipe inputs, all modes, EN/AR: no fault |
| **Clock rules** (new) | 19 new checks: valid / invalid / missed reads (1–4) / recovery / VL loss / no stale time after loss / millis wrap; face shows the time for every demo × phone × validity combination (test fails on RC1: 12 findings) |
| Charge debounce (new) | flipping pin: shown state unchanged; real plug / unplug after 3 samples |
| Time (all days 2024–2099) | 50 checks, 0 failed |
| Rendering | 811 states / 279,653 checks / 0 findings; 6 `face__not-synced` reference pictures deliberately updated (they now show the time); other 126 byte-identical |
| UI soak | 30,000 inputs, LVGL 8,176–8,208 B (no growth), sampled peak 15,208 B |
| Performance budgets | 0 failures (cockpit update 1.71 M, pages rebuild 6.19 M instructions, CI) |
| LVGL pool 32 / 16 KB | 811/811 identical |
| Install simulation | RC2 update / rollback to RC1 / R-B / verify failure / unpinned / wrong base: 0 failures (incl. real-size write plan) |
| Boot emulator S10 | RC1 → RC2 write cut at every point: factory app starts; complete RC2 starts once — passed |

## Memory (static, CI)
IRAM 72,464 B (unchanged); DRAM static 97,336 B (+144 B vs RC1: clock keeper, debounce, cause text). Image +3,072 B.

## Not fixed / open
- **D7 unexplained restart (release blocker):** see STAGE1_3_HW_RESULTS.md and the restart investigation section there.
- **P1 periodic full-screen rebuild:** cause not proven on hardware. RC2 hardens the two device-only candidates (charge
  pin, clock reads) and prints the cause of every rebuild, so one RC2 session settles it.
- Ride update slower than Stage 1.1 (p50 85–91 ms vs 71 ms) — known cost of IRAM drawing off (needed for Bluetooth).
