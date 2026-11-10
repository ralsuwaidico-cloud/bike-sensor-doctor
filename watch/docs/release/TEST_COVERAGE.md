# Cyclift Watch — test coverage, Stage 1.3 RC1 (11 Nov 2026)

All tests below run on the computer and in CI (workflow `watch.yml`). None of them proves behaviour on the watch; the
hardware checks are in HARDWARE_ACCEPTANCE.md. Numbers are from the local run of 11 Nov and CI run 42916312090 on commit 6854b9b (all 6 jobs green; CI instruction counts differ slightly from the local machine, e.g. new pages 6.19 M in CI vs 6.38 M locally).

| Suite | File | What it checks | Result |
|---|---|---|---|
| Model | `test/v3/test_model.cpp` | ride states, pending commands, refusals, toasts, settings, menu, keys | 1,720 checks, 0 failed |
| Navigation oracle | `test/v3/test_nav.cpp` | **every screen × every input** (4 swipes, Key 1, Key 2, Key 1 hold, taps) in English and Arabic and during a ride, against a table written from prototype v3.3; repeated gestures never stack duplicates; history ≤ 8; Quick Settings rows; lock; Today Start banner | 353 checks, 0 failed |
| Navigation soak | `test_nav.cpp` | 200,000 random inputs; history bound and "back always reaches home" every 5,000 inputs | 0 failed |
| Time | `test/v3/test_time.cpp` | clock-chip registers, invalid-clock detection, serial `T` parser; **every day 2024–2099 against an independent calendar** (27,759 days, 19 leap days, every midnight rollover incl. month and year ends, weekday) | 31 checks (one covers all 27,759 days), 0 failed |
| Rendering | `test/v3/host_main.cpp` (`make render`) | 811 pictures: every RC1 screen × 6 themes × EN/AR × Standard/Focused/Large Text, demo and honest data, special states. Per picture: inside the round glass, no text overlap or clipping, every glyph present (Arabic shaped), touch targets ≥ 44 px and not overlapping, overlays never cover a control, **text contrast ≥ 3:1** | 279,605 checks, 0 open findings, 0 known defects |
| Date sweep | `host_main.cpp` | every month × weekday × widest day number on the face and Today, EN/AR × 3 densities (check-only, no pictures) | included above; found and fixed a 1 px Arabic header overlap |
| Touch | `host_main.cpp` | taps through the real drawn touch areas: menu rows, Quick Settings rows, Week link, Start, Why?, Pause | 0 failed |
| UI soak | `host_main.cpp` | 30,000 random inputs through the real UI, each rendered; LVGL memory at a fixed reference state every 1,000 inputs | reference 8,176–8,208 B (no growth), sampled pool peak 15,208 B |
| Pixel regression | `perf_check.py` | 132 Stage 1 pictures byte-identical to the approved rendering | 132 / 132 identical |
| Partial updates | `perf_check.py` | 1,162 partial-update frames (incl. the new pages) equal a full redraw | 0 differ |
| Performance budgets | `perf_check.py --callgrind` | cockpit update ≤ 2.0 M instructions, rebuild ≤ 5.5 M, navigation ≤ 6.0 M, **new pages rebuild ≤ 7.0 M** (measured 6.38 M), idle ≤ 0.02 M, ≤ 1.1 redraws/s, ≤ 23,000 px per cockpit update | 0 failures |
| LVGL pool study | `pool_study.sh` | all 811 RC1 states at 32 KB and 16 KB pools | 811/811 pictures identical to 64 KB at both sizes (CI); 12 KB failed in the Stage 1.2 study |
| Install simulation | `tools/stage2a/test_reinstall_sim.py` | Stage 1 install, B1 reinstall, R-A, R-B, Stage 1.1 update, Stage 1.2 update, **RC1 update (section 10)**: one write at 0x400000, first 4 MB untouched, rollbacks, verify failure, wrong / unpinned fingerprint, wrong starting state | 52 checks, 0 failed |
| Boot emulator | CI job boot-sim (QEMU) | all scenarios; S10 = Stage 1.1 → RC1 write cut at 25/50/75/99 %, last sector missing, one bit flipped, header erased → factory app starts; complete RC1 starts once | 0 failures (CI 42916312090) |
| Firmware build | CI | V1_0 / V1_1 / V2 RC1 images, header DIO/40m/8MB, reproducible double build, fingerprints of Stage 1 / 1.1 / 1.2 unchanged | passed (CI 42916312090) |

Not covered (needs the watch): real touch accuracy, backlight levels, button hold timing, ESP32 frame times for the new
pages, internal heap with the new fonts, Arabic legibility on the panel, battery (none fitted).
