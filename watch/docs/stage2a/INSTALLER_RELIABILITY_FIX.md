# Installer and recovery scripts — reliability fix (9 Nov 2026)

## Problem
`cy_install.py` and `cy_recover_b.py` ran `esptool … --before default_reset --after no_reset` for every command. The checkpoints
reset the watch into its firmware, but the **last** command of the install session (full read) and of Recovery B (read-back +
verify) left the ESP32 in its ROM download mode. The watch then showed a black screen until USB was reconnected.

## Fix
New shared module `watch/tools/stage2a/device_session.py`; both runners (`pc_install_runner.py` = `cy_install.py`,
`pc_recovery_b_runner.py` = `cy_recover_b.py`) and the read-only tool `stage2a_readonly.py` use it.

| Requirement | How it is met |
|---|---|
| Every normal completion restarts the firmware | `run_phase()` always ends with `restart_and_confirm()` (EN pulse with IO0 high) |
| Expected failures and exceptions trigger cleanup and a restart attempt | planned stops (`Stop`) and any other exception (USB error, serial error, Ctrl-C) go through the same final restart |
| Cleanup cannot hide the original error | the original exception is logged first and re-raised unchanged; a failing cleanup is only logged |
| Flash verification ≠ application boot | logs say `FLASH VERIFIED` / `FLASH VERIFY FAILED` and, separately, `BOOT CONFIRMED` / `BOOT NOT CONFIRMED`; a phase passes only if both its work passed and the boot was confirmed |
| Boot confirmation | ROM banner `boot:0x13 (SPI_FAST_FLASH_BOOT)`, exactly one start within the window, no `DOWNLOAD_BOOT`, plus the expected firmware marker (`Cyclift v3 proof of concept`) or absence of it for the factory firmware |
| Serial monitoring only in normal execution | `listen()` refuses unless the session state is `running` (confirmed boot) |
| Restart cannot be confirmed | log line `STOP: the watch could not be confirmed running its firmware. Do not continue. Disconnect and reconnect USB…`; the read-only tool exits with code 4 |

A restart is **not guaranteed** after every failure: if the USB link is lost, the port is held by another program, or the board
has no power, the script cannot reach the chip. In those cases it reports "BOOT NOT CONFIRMED" and stops; the owner reconnects USB.

## Tests (CI job `v3-stage1-host`, `test_device_session.py`, 40 checks, fake watch — no hardware)
install + restart · read-only verify + restart · read + restart · recovery R-A through the real runner · verify failure + cleanup
· interrupted esptool (original error propagates; chip restarted) · USB gone during cleanup (original error kept, boot NOT
confirmed, STOP message) · serial port cannot open · serial read error · no boot output (timeout) · IO0 stuck (download boot)
· reset loop · wrong firmware marker · monitoring refused in download mode · 40 randomised repeated runs never leave the chip in
download mode · no failure path prints BOOT CONFIRMED or PHASE PASSED · a failing cleanup never replaces the original error ·
static check: the runners contain no direct `subprocess`, `serial.Serial` or `no_reset`.

What these tests do **not** prove: behaviour of the real CH9102 auto-reset circuit and the real ROM. The restart method (RTS pulse
with DTR released) is the same one the checkpoints C1–C4 used successfully on the watch on 9 Nov 2026.

## PC copies
The updated scripts are **not yet copied to the PC**. Before the next hardware session the copies in
`Documents\Cyclift_Stage2a\tools\` must be replaced by the repository versions (`device_session.py` is new) — part of the
approval request in `STAGE1_HARDWARE_VALIDATION_PLAN.md`.
