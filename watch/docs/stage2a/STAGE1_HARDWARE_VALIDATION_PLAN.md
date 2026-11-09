# Cyclift Watch — next Stage 1 hardware validation plan (draft for review, 9 Nov 2026)

Nothing in this plan has been run. Part A needs only the factory firmware already on the watch. Part B needs Cyclift Stage 1
re-installed and therefore a **new owner approval**. Bluetooth integration and Stage 2b remain out of scope.

## Preconditions (before any part)
* PC scripts replaced by the repository versions with the reliability fix (`device_session.py` new; `cy_install.py`,
  `cy_recover_b.py`, `stage2a_readonly.py` updated) — approval **A0** (copying files on the PC only, no watch access).
* Razer Synapse and any other program using COM4 closed. Watch charged, T-U2T on COM4.
* Every scripted step must end with `BOOT CONFIRMED`. If a step ends with `BOOT NOT CONFIRMED`, stop, reconnect USB, report.

## Part A — factory firmware only (no writes; approval A1: read-only serial session)
| ID | Test | Method | Pass criterion |
|---|---|---|---|
| A-1 | Screen + backlight | look at the face after a USB reconnect and after a reset by the script | face visible, backlight on |
| A-2 | Upper button (GPIO35) | press; owner notes the reaction | factory UI reacts |
| A-3 | Lower button (GPIO34) | press; owner notes the reaction | factory UI reacts |
| A-4 | Touch taps | tap 5 marked points (centre, 4 edges) | factory UI reacts to each — establishes whether the touch hardware works independently of Cyclift |
| A-5 | Touch swipes | swipe up/down/left/right ×3 | factory UI reacts |
| A-6 | Reset and reboot | script restart ×3 (read-only), then boot check | 3 × `BOOT CONFIRMED`, face returns each time |
| A-7 | USB reconnection | unplug 10 s, plug in ×3 | face returns each time |
| A-8 | Serial stability | 5 min listening after a confirmed boot | no unexpected restart in the log |
| A-9 | End state | final script step | `BOOT CONFIRMED`, factory face visible |

A-4/A-5 decide the touch question: if touch fails here too, it is hardware/connection; if it works here, the cause is in Stage 1.

## Part B — Cyclift Stage 1 re-installed (approvals B1 install, B2 hands-on tests, B3 rollback if needed)
### Install method (unchanged plan, fixed scripts)
Same factory-preserving procedure as `FIRST_INSTALL_PROCEDURE.md`, same approved file `faa2828f…cba7`, same four sectors in the
same order: app → 0x400000, bootloader size field 0x1000 + 0x5000, partition table 0x8000, OTA record 0xF000. The upper flash
already holds the same Stage 1 image (verified after Recovery B), so Phase 1 is a verify-then-write of identical data.
Each phase ends with a restart and boot check; phases run one at a time with the owner's go-ahead.
The last step of the session is a restart with `BOOT CONFIRMED` + Cyclift banner — never a flash read.

### Hands-on tests (serial commands from the PC are test hooks only; they do not write flash)
| ID | Test | Method | Pass criterion |
|---|---|---|---|
| V2-1 | Screen stays on | after install, watch for 5 min | interface visible the whole time; closes the black-screen question |
| V2-2 | Rendering and navigation | walk every screen with the buttons | each screen draws completely, no tearing/garbage, ≤ 1 s per change |
| V2-3 | Upper button | short presses on each screen | expected action (logged as key 1) |
| V2-4 | Lower button | short presses on each screen | expected action (logged as key 2) |
| V2-5 | Touch taps | 5 marked points on home and cockpit | UI reacts where an action exists (Stage 1 logs resulting actions, **not raw tap coordinates** — a tap on an area without an action leaves no trace; raw touch logging would need a new build) |
| V2-6 | Touch swipes | 4 directions ×3 | screen changes where a swipe is defined; resulting action logged |
| V2-7 | Cycling cockpit + simulated metrics | serial `r` (start ride), `p` (pause/resume), `s` (sensor sets: all → no power → HR only → none) | values update; missing sensors shown as missing, never as zero |
| V2-8 | Arabic interface | serial `l` | Arabic text renders right-to-left, no missing glyphs, layout not clipped |
| V2-9 | Text density | serial `d` (density), `t` (large text), in English and Arabic | no overlap or truncation of key numbers |
| V2-10 | Reset and reboot | script restart ×3 | 3 × `BOOT CONFIRMED` with Cyclift banner |
| V2-11 | USB reconnection | unplug/plug ×3 | Cyclift returns each time |
| V2-12 | Serial logs and stability | 10 min with a ride running, `u` performance reports | no restart; frame time and free memory stable |
| V2-13 | End state | final step | `BOOT CONFIRMED`; owner confirms the screen is on |

Evidence recorded per test: log extract (from `install_log.txt`, private), owner's note, photo optional (no identifiers).

## Rollback
* **R-A** (any problem after the switch): write the original OTA record 0xF000 → factory app selected; restart + boot check.
* **R-B** (R-A insufficient or the owner wants factory state): original 0xF000 → 0x8000 → 0x1000 + 0x5000, each verified;
  restart + boot check; Cyclift left in the upper flash. Already performed successfully once (9 Nov 2026).
* **R-C** (last resort, separate approval): write the full 8 MB backup `77ad7105…`.
Each rollback now ends with a restart and `BOOT CONFIRMED`/`NOT CONFIRMED`; no improvised flash operations.

## Required approvals
| ID | Scope |
|---|---|
| A0 | copy the updated scripts to the PC tools folder (no watch access) |
| A1 | Part A read-only session (serial + script restarts; no writes) |
| B1 | re-install Stage 1 `faa2828f…` with the factory-preserving procedure (writes four sectors; app region already identical) |
| B2 | Part B hands-on tests (serial test hooks; no writes) |
| B3 | rollback R-A / R-B if a test fails or at the owner's request (R-C only with separate approval) |
Not requested: diagnostic display firmware, a rebuilt Stage 1 binary, Bluetooth, Stage 2b, partition changes beyond the plan.

## Status 9 Nov 2026 21:10 — Part A done (see A1_FACTORY_VALIDATION_RESULTS.md)
A0 and A1 completed; all Part A tests pass except touch, which does not respond in the factory Touch tool either.
B1–B3 not approved and not run.

## Status 9 Nov 2026 22:46 — Part B: B1 done, B2 done (13/13 PASS, see B2_HARDWARE_VALIDATION_RESULTS.md). B3 not approved.
