# Firmware 0.7.2 crash loop — independent investigation (26 Oct 2026)

**Situation.** The owner installed 0.7.2 (app SHA-256 `33b42502…`). While he was connecting (phone and/or power meter) the
board showed **SAFE MODE — "3 crashes in a row, last reset: crash (panic)"**. Core dumps were disabled in 0.7.2
(`CONFIG_ESP_COREDUMP_ENABLE_TO_NONE=y`), so no dump exists; no serial log of the crash has arrived yet
(`pc-kit/CAPTURE-CRASH.ps1` will produce `crash-log-<time>.txt` if the owner runs it).

**Bottom line.** The crash is **not reproduced** without hardware and **no root cause is claimed**. The investigation found
three concrete defects in the 0.7.2 Bluetooth code that can each end in a panic on the device, and several smaller ones; all are
fixed in 0.7.3, which also stores the evidence (core dump + last log lines + event log) so the next crash identifies itself.
Section 7 lists exactly what the crash log must show to tell the hypotheses apart.

Exact 0.7.2 source: `ec0aad9` (verified: `git log -1 2cb69ff` = 0.7.1, `ec0aad9` = 0.7.2). A rebuild of `ec0aad9`
(`/home/claude/ws-fw`, `build/bike_computer.elf`) matches the installed binary except 70 timestamp bytes, so every address below
is the installed firmware's address.

---

## 1. What the SAFE MODE screen tells us (facts, before any hypothesis)

`main.c` (0.7.2) counts a reset as a crash for `ESP_RST_PANIC / INT_WDT / TASK_WDT / WDT / BROWNOUT`, clears the counter
after **20 s** without a crash (`stable_cb`), and enters SAFE MODE at 3. The screen printed the **last** reset reason:
"crash (panic)" = `ESP_RST_PANIC`.

* **Three crashes, each within 20 s of the previous start.** After the first crash, two more boots crashed before the 20 s
  timer. Whatever crashes does so **early and repeatably** after a start — i.e. in something that starts by itself: the paired
  power meter's connect / discovery / subscription sequence (scan begins ~1 s after start; recovery timers fire at 8 s and 15 s
  after subscribing) and/or the bonded iPhone reconnecting while Cyclift is open. Ordinary UI navigation is unlikely (after a
  reset the board shows Home).
* **Panic, not watchdog.** With this sdkconfig: the task watchdog does **not** panic (`CONFIG_ESP_TASK_WDT_PANIC` unset), an
  interrupt-watchdog reset is reported as `ESP_RST_INT_WDT` ("interrupt watchdog"), an LVGL assert spins in `while(1)` (screen
  freeze, no reset), a brownout prints "brownout". **ESP_RST_PANIC** therefore means an exception (Load/StoreProhibited,
  IllegalInstruction, …), an `abort()` (failed `assert`, `ESP_ERROR_CHECK`, FreeRTOS `configASSERT`, NimBLE assert, heap
  corruption check) or the **FreeRTOS stack-overflow check** (`CONFIG_FREERTOS_CHECK_STACKOVERFLOW_CANARY=y` → abort).
* The last reset reason only describes the third crash; the first two may differ.

## 2. Every 0.7.2 change, by task / context (`git diff 2cb69ff ec0aad9 -- firmware/waveshare`, 47 files, +2269/−378)

| Change (0.7.2) | Runs in | Shared state / locking | Buffers, stack |
|---|---|---|---|
| `bc_gatt.c` (pure: find chr, own CCCD range, CCCD value, service order) | NimBLE host task (from callbacks) | arrays inside `link_t` | bounded by `NCH`/`NDS` checks; no OOB found (host tests + fuzz) |
| `bc_pipe.c` stages + recovery (`bc_pipe_tick`), hex keep (3×20 B) | host task (`bc_pipe_packet`, `_subscribed`, `_error`) **and ble_mgr task** (`bc_pipe_tick` in `tick()`) | `LOCK()` = `portENTER_CRITICAL(&s_mux)` around every call | `bc_pipe_hex` bounded (`o+4<=cap`) |
| `bc_cp.c` standard Cycling Power decoder | host task (NOTIFY_RX) | under `LOCK()` | length-checked |
| `ble_central.c` new chain: all services → all characteristics → own descriptor range → CCCD write → **`ble_gattc_read` read-back** (`on_cccd_read`) | host task callbacks | `link_t` fields written **without** lock (only `bc_pipe`/decoders are locked) | `pipe_log()` `char line[128]` on every stage change |
| **Recovery actions** RESUBSCRIBE → `disc_begin()` (rediscovery) and RECONNECT → `ble_gap_terminate()`; DUMP_HEX (`char h[64]`) | **ble_mgr task** (`tick()` via `mgr_task`, `ble_central.c:438-464`, task created at `:523`, 4096 B stack) | **the same `link_t` fields the host callbacks change, no lock** | see §3 |
| MTU fallback (`mtu_fallback`, `:261`) → `start_discovery` → **`disc_begin`** (now `ble_gattc_disc_all_svcs`) | **esp_timer task** (3584 B stack) — races `on_mtu` → `start_discovery` on the host task | `disc_started` check-then-set, no lock | |
| `app_psvc.c` SENSOR_DIAG (`sd_scan`, emission in `app_psvc_next`) | LVGL/app task (`app_tick` 250 ms) | `plat_sensors()` snapshot (spinlock copy) | `plat_sensors_t` on stack (~450 B) ×2 |
| LIVE ages (`app.c`) | LVGL/app task | — | — |
| `plat_link_info_t` new fields (stage, err[21], handles, counters) | snapshot copy under `LOCK()` | — | `snprintf` bounded |
| `ui_conn.c` rewrite (table rows, detail pages), `ui_wifi.c`, `ui_tools.c` (Device Health + 320 B sensor lines), `ui_home.c` | LVGL task only (no UI code is called from Bluetooth callbacks — verified by call graph) | `ui_conn_row_status()` calls `app_live()` + `plat_phone_status()` per row → **`count_bonds()` → NimBLE host lock** whenever the phone is not connected | 2000 B / 3400 B **static** buffers; stack OK (LVGL task 12 KB) |
| `main.c` `health()` `line[200]→[320]`, longer health line | main task, **without the LVGL lock** while `app_live()` reads app state the LVGL task writes | none | `snprintf` bounded: no overflow (worst case 243 chars of 320) |

Every `snprintf/memcpy/strcat` added in 0.7.2 was checked: all bounded (`sizeof` destinations, `n<=20` copies, `%.Ns`).
The only `strcat` (`ui_conn.c` "Other Bluetooth" tags) writes at most 21 bytes into `char tag[24]`.

## 3. Stack (compiled with `-fstack-usage -fcallgraph-info=su`, scratch build of the exact 0.7.2 tree)

Tool: `tools/cistack.py` (+ `tools/cistack_edges.txt`) walks GCC call-graph files of the whole ESP-IDF build, adds the NimBLE dispatch edges that
are indirect calls (event loop → HCI/ATT/GATT dispatch → our callbacks), and frame sizes of prebuilt newlib from the Xtensa
`entry a1, N` instructions. Logging costs a lot: `ESP_LOGx` → `esp_log` (96 B) → `vprintf` → `_vfprintf_r` (800 B) →
`__sbprintf` (288 B) → `_vfiprintf_r` (704 B) … = **2128 B for one log call**.

| Path (0.7.2) | Worst case | Task stack |
|---|---|---|
| host: ATT response → `on_svc` → `try_next_service` → `fail` → `set_state` → `pipe_log` → `ESP_LOG` | **3008 B** | nimble_host **4096 B** |
| host: write response → `on_cccd` → `on_cccd_read` → `fail` → … → `ESP_LOG` | **2960 B** | 4096 |
| host: notification → `gap_event` (256 B frame) → `pipe_log` → `ESP_LOG` (first VALID) | ~3040 B | 4096 |
| host: HCI disconnect / SM paths → `gap_event` → `connect_to` → `adv_start` (384 B) → NimBLE HCI → `esp_log` | up to **4016 B** (static upper bound) | 4096 |
| ble_mgr: `tick` → `ble_link_tick` (400 B) → `adv_start` → … → log | 3424–3456 B | ble_mgr **4096 B** |
| esp_timer: `mtu_fallback` → `disc_begin` → `fail` → `ble_gap_terminate` → log | 2576 B (+ timer task frames) | esp_timer **3584 B** |

Plus, on the task stack, the interrupt context save (~0.25–0.4 KB on Xtensa) and register-window spills. **Margins of
0.6–1 KB, and the static worst case reaches the 4 KB limit.** 0.7.2 added `pipe_log`'s 160 B frame and several log calls to
callbacks that run inside the host task. This is a credible stack-overflow mechanism (the canary check aborts → "panic"); it is
**not proven**: no stack high-water mark of 0.7.2 under a connecting meter was ever recorded (the 60 s health line prints
`stack-free … nimble N`, but no log of it exists).

0.7.3: host task 4096 → **7168 B** (it now also runs the sensor manager, worst case 3504 B: `tick_ev` → `tick` →
`ble_link_tick` → … → log), esp_timer 3584 → **4608 B**, ble_mgr 4096 → 3072 B (it only posts events now; worst 208 B).
The 0.7.3 log hook (`diag_esp.c`, one `vsnprintf` into a 192 B line + `fwrite`) costs **1504 B** instead of 2128 B per log
call, in every task. Every stack high-water mark is now logged every 60 s and written to the event log.

## 4. Lifetime / races (ThreadSanitizer + a fake-NimBLE harness, §5)

1. **`count_bonds()` inside `portENTER_CRITICAL` — confirmed defect (since 0.7.0).** `ble_link.c:260` (phone CONNECT) and
   `:244` (`on_disconnect`) and `:312` call `count_bonds()` → `ble_store_util_count()` → `ble_store_read()` →
   **`ble_hs_lock()` (a FreeRTOS mutex)** while holding the `s_mux` spinlock with interrupts masked. If any other task holds the
   NimBLE host lock at that moment — the ble_mgr task (same core, preempted inside `ble_gattc_*`, `ble_gap_conn_rssi`,
   `ble_gatts_notify_custom`) or the LVGL task (`plat_phone_status()` → `count_bonds()`, called by every Connections row, the
   Home summary and SENSOR_DIAG bookkeeping whenever the phone is not connected) — `xQueueSemaphoreTake` "blocks" with interrupts
   masked: `vTaskPlaceOnEventList` + a yield that cannot happen, then it loops. Outcome on the chip: **interrupt-watchdog reset**,
   or FreeRTOS list corruption (the task sits in the delayed/event lists while running) → later **exception/assert = panic**.
   The harness counted it on **every** phone connect and disconnect (2000 times in 1000 cycles). 0.7.2 raised the chance of
   contention: the LVGL task now takes the host lock several times per 250 ms refresh while the phone is disconnected (the moment
   the phone (re)connects), and the ble_mgr task now runs GATT procedures (re-subscribe) and disconnects.
2. **Recovery actions on the wrong task — confirmed race (new in 0.7.2).** `tick()` (ble_mgr) calls `disc_begin()` /
   `ble_gap_terminate()` and reads/writes `link_t` (`nsv/nch/nds/svc_try/val/cccd/state_since`, `s_connecting`, `s_scanning`)
   while host callbacks change the same fields. TSan, 300 phone cycles on the real 0.7.2 `ble_central.c`/`ble_link.c`: **41
   data-race reports**, e.g. `tick :465` vs `set_state :120`, `tick :446/:478-482` vs `gap_event :382/:419-420`,
   `try_next_service :216` vs the snapshot, `scan_start/stop` vs `gap_event`. In the compiled 0.7.2 code these are memory-safe
   (static link structs, every array write re-checks its bound, `s_connecting` is loaded once — checked in the disassembly at
   `tick+0x1b6`), so the expected effect is wrong behaviour (duplicate discoveries, a re-subscribe on a link that just
   disconnected, a stale `l->conn`) rather than a direct panic — unless NimBLE itself asserts on the overlapping procedures.
3. **Double discovery — confirmed race.** `mtu_fallback` (esp_timer task) and `on_mtu` (host) both run
   `start_discovery()`; `disc_started` is check-then-set. Two `ble_gattc_disc_all_svcs` on one link interleave their answers
   into the same arrays (bounded) and each one's EDONE starts another characteristic discovery; with `GATT_MAX_PROCS=4` and three
   links this can exhaust procedures (→ `fail()` → reconnect loop).
4. **Stale callbacks** (an answer from a discovery replaced by a re-subscribe, or from a previous connection on the same handle)
   were applied to the current link — 0.7.3 tags every GATT callback with slot + discovery generation and ignores stale ones.
5. **Phone-disconnect reset on the wrong task** (since 0.7.0): `ble_link.c:246` calls `app_psvc_on_disconnect()` on the host
   task, which resets `app_psvc` state the app task is using (`app_psvc.c:425`). Memory-safe, but a race; 0.7.3 hands it over
   as a flag.
6. **`health()` without the LVGL lock** (`main.c:100`): `app_live()` reads ride/profile state the LVGL task writes. 0.7.3 takes
   the lock.
7. Checked and **not** a problem: SENSOR_DIAG while the phone connection closes (`plat_phone_notify_svc` drops when not
   connected; `ble_gatts_notify_custom` always consumes the mbuf — the harness counted 0 leaked mbufs over 12 490 notifications);
   no UI/LVGL call from any Bluetooth callback; notify-after-free impossible (no heap objects in the link path).

## 5. Host-side tools and results

| Tool | Scope | 0.7.2 | 0.7.3 |
|---|---|---|---|
| **BLE glue stress** `test/blehost` (new): the **real** `ble_central.c` + `ble_link.c` on a fake NimBLE with the device's task layout (host thread, ble_mgr, esp_timer, app/UI thread, phone, chaos). Faults: disconnect during any GATT procedure, ATT errors, ENOMEM, no MTU answer, CCCD read-back mismatch/failure, malformed/short/long notifications (0-39 B), notifications on other handles, connect failures, meter in/out of range, silent meter (re-subscribe / reconnect paths), RETRY re-pairs, standby, pairing scans racing | ASan+UBSan, 1000 phone cycles (1723 s virtual, 101 meter connections, 548 GATT procedures, 3955 notifications of which 249 malformed): **no memory error**; invariant **"NimBLE host lock taken inside portENTER_CRITICAL": 2000 violations**. TSan 300 cycles: **41 race reports** | ASan+UBSan 1000 cycles (1774 s virtual, 118 meter connections, 662 procedures, 3759 notifications / 210 malformed, 17 500 host-task events): **PASS, 0 violations**, 0 sensor GATT operations on the phone's connection, 0 non-CCCD writes, 0 leaked mbufs. TSan 300 cycles: 20 reports, all single-byte request/enable flags written by the UI and read by the host task (by design) — no compound link state |
| Host unit tests (`test/host`, ASan+UBSan, `-fno-sanitize-recover`) | bc_core | 2216 checks pass | **2403 checks, 0 failed** (xds 228, core 1899, pipe 89, diag 124 incl. 20 000-message fuzz of the 1.2.3 server, partitions 63) |
| PC harness (`test/sim`, real UI/app code) plain and **ASan+UBSan** | UI + app | 283 screens / 455 checks | **289 screens / 489 checks, 0 failed**, both builds; stress scenario 22: 1000 rapid phone connect/disconnect cycles (735 s simulated) with SENSOR_DIAG (1125 events), 425 report requests, 1004 meter changes, 252 Wi-Fi toggles, 248 malformed writes: clean |
| cppcheck 2.22 (`--enable=warning,portability,performance`) | bc_core / main + app + ui | — | bc_core: 0 findings. main: 2 false positives in `net_wifi.c` (zero-length copies), `ui_tools.c` "overlapping snprintf" (false: `K` is a source string), 1 real but harmless `%u` with a promoted `int` (`ui_settings.c`, fixed) |
| `gcc -fanalyzer` | 15 bc_core files + 19 app/UI/BLE files | — | **0 warnings** |

## 6. QEMU

The installed ESP-IDF has `qemu-system-xtensa` **esp_develop_9.0.0_20240606 with an `esp32s3` machine**. Booting the exact
0.7.2 image: the 2nd-stage bootloader runs, reads the partition table, boots `ota_0`, then the app **aborts in `cpu_start`:
"quad_psram: PSRAM chip is not connected"** (this QEMU does not emulate the board's quad PSRAM; octal also fails). A scratch
build of the same source with `CONFIG_SPIRAM_IGNORE_NOTFOUND=y` gets through ESP-IDF start-up (heap init, flash detection,
eFuse) and then produces no further output before `app_main` (peripheral emulation). The Bluetooth controller is not emulated
at all. **QEMU cannot reach the code under suspicion**; it only confirms that the 0.7.2 image, bootloader and partition table
are well-formed up to app start.

## 7. Conclusion: ranked hypotheses and what the crash log must show

No hypothesis is confirmed. Ranked by fit with "panic, three times within 20 s of start, while connecting":

| # | Hypothesis | Fits because | The crash log (CAPTURE-CRASH / 0.7.3 report) shows |
|---|---|---|---|
| **H1** | **Stack overflow in `nimble_host`** (4 KB) — or `ble_mgr` / `esp_timer` — on a GATT/GAP callback path that logs (0.7.2 added logging and a 160 B frame to these paths) | panic via the canary check; happens during connect/discovery/subscribe, automatically after every start | `***ERROR*** A stack overflow in task nimble_host has been detected.` (or `ble_mgr` / `esp_timer`), or `Stack canary watchpoint triggered (nimble_host)`; backtrace through `vprintf/_vfprintf_r/esp_log` with PCs in `on_svc 0x4200E94C-0x4200E9B1`, `try_next_service 0x4200E868-0x4200E94B`, `on_chr 0x4200E9B4-0x4200EADD`, `on_dsc 0x4200EAE0-0x4200EBC4`, `on_cccd_read 0x4200EBC4-0x4200EC9C`, `fail 0x4200E71C-0x4200E7CE`, `pipe_log 0x4200E62C-0x4200E67B`, `gap_event 0x4200F4BC-0x4200FB8C`, `tick 0x4200F048-0x4200F404` |
| **H2** | **NimBLE host lock taken inside a spinlock** (`count_bonds` at `ble_link.c:244/260/312`) contended by ble_mgr or the LVGL task when the phone (re)connects | happens exactly at phone connect/disconnect; Cyclift reconnects by itself after every start | `Interrupt wdt timeout on CPU0` **or** an `assert failed` / exception inside FreeRTOS (`vTaskPlaceOnEventList`, `xTaskPriorityInherit`, `uxListRemove`, `vTaskSwitchContext`, `xQueueSemaphoreTake`) with `gap_cb 0x42010AC4-0x42010F36` / `on_disconnect 0x42010A10-0x42010AC4` → `count_bonds 0x420109F8-0x42010A0D` → `ble_store_util_count` → `ble_hs_lock` in the backtrace of task `nimble_host` |
| **H3** | NimBLE assert from overlapping GATT procedures started by the ble_mgr recovery (`disc_begin` at `ble_central.c:452`) or the MTU-fallback double discovery | the meter is silent when not pedalled → re-subscribe at 8 s, reconnect at 15 s — inside the 20 s window | `assert failed:` in a `ble_gattc_*` / `ble_att_*` / `ble_hs_*` function, task `ble_mgr` (PC in `tick` / `disc_begin 0x4200E7D0-0x4200E81A`) or `esp_timer` (`mtu_fallback 0x4200E840-0x4200E866`) |
| H4 | Something outside Bluetooth (UI, Wi-Fi, app logic) | weaker: would not need a connection | panic in task `taskLVGL` / `wifi_mgr` / `main` with PCs outside the ranges above |

Decode any address with: `xtensa-esp32s3-elf-addr2line -pfiaC -e /home/claude/ws-fw/firmware/waveshare/build/bike_computer.elf <addresses>`.
If the log only shows `rst:0xc (RTC_SW_CPU_RST)` lines without a "Guru Meditation" / "abort()" block, the panic text was lost
before USB enumerated; then the 0.7.3 crash report (core dump summary + the 2 KB of log before the reset, kept in RTC memory)
is the evidence that is still missing.

## 8. Defects and their status in 0.7.3 (each with a regression test)

| Defect | Status | Fix (0.7.3) | Test |
|---|---|---|---|
| D1 NimBLE host lock inside `portENTER_CRITICAL` (`count_bonds`, 3 places) | **confirmed** (harness: 2000/2000 phone events) | `count_bonds()` outside the spinlock; returns the cached count when NimBLE is not running | `test/blehost` invariant "host lock inside critical section" = 0 |
| D2 recovery actions + stuck-connect handling on ble_mgr, racing host callbacks | **confirmed** (TSan 41 reports) | all link work on the host task: ble_mgr / esp_timer / UI only post `ble_npl` events or set request flags | TSan: no compound link-state race left; blehost PASS |
| D3 double discovery (MTU answer vs 2 s fallback) | **confirmed by code** | fallback runs on the host task and checks the connection handle it was armed for | blehost with 6 % MTU answers dropped |
| D4 stale GATT callbacks applied to a newer discovery / connection | **confirmed by code** | `arg` = slot + discovery generation; re-subscribe never starts while a discovery is in flight; 20 s set-up timeout | blehost (disconnects inside every procedure type) |
| D5 nimble_host 4 KB / esp_timer 3.5 KB stacks with ~0.6–1 KB margin | **fixed defensively** (unproven) | 7168 / 4608 B; log calls 30 % cheaper; high-water marks logged + event log + alert < 512 B | stack analysis (§3) |
| D6 `app_psvc_on_disconnect` on the host task | fixed defensively | flag, applied by the app task | sim scenarios 12-22 |
| D7 `health()` reads app state without the LVGL lock | fixed defensively | under `lvgl_port_lock` | — (device only) |
| D8 UI-task Bluetooth calls (`plat_phone_set_enabled`, `plat_phone_disconnect`, standby) | fixed defensively | flags applied in `ble_link_tick` on the host task | blehost (UI toggles racing) |
| D9 personal identifiers in logs (full identity address, IP, sensor names) | fixed (privacy, for the reports) | last 2 bytes only, IP / names removed; report redaction filter | `test_bc_diag` privacy checks |
| The 0.7.2 crash itself | **unconfirmed** | evidence now persists: core dump (flash), RTC log tail, event log, reports | needs the hardware |

Re-verified unchanged in 0.7.3: the 0.7.2 power-meter CCCD fix (`bc_gatt_pick_cccd`, own descriptor range, `01 00` only,
read-back; `test_bc_pipe` + blehost invariant "non-CCCD writes to a sensor = 0") and the LIVE ages (`app.c publish_live`,
sim scenario 20f).
