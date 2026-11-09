# A1 — factory-firmware hardware validation results (9 Nov 2026, 20:47–21:10 Dubai)

Approved scope: A0 (copy scripts) and A1 (read-only factory tests). B1/B2/B3 not approved and not done. No flash write, erase,
partition change, eFuse access or rollback was performed.

## CI and script copy (A0)
* CI run 42655663938 (commit e8181d9): all 5 jobs passed (host-tests, v3-stage1-host, firmware-compile,
  publish-stage1-candidates, stage2a-boot-sim); every step succeeded, none skipped. `test_device_session.py`: 40 ok, 0 failures.
* PC `Documents\Cyclift_Stage2a\tools\`: old versions kept in `backup_pre_fix_20261109\` (read back, byte-identical to the
  originals). New files read back from the PC and compared by SHA-256 with commit e8181d9: all 7 identical
  (device_session 6c2e3d91…, cy_install bcf4b00d…, cy_recover_b 996151aa…, stage2a_readonly d460765b…, fp_plan 3fcfafcb…,
  install_check 0362cc44…, check_image_header acf983fb…). Manifest: `tools\MANIFEST_A0.txt`.
* A1 test script `a1_factory_tests.py` added (refuses every esptool command except flash_id and read_flash).

## Results on the real watch (CH9102 T-U2T, COM4)
| ID | Test | Result | Evidence |
|---|---|---|---|
| A-0 | Read-only identification + restart | **PASS** | chip ESP32-PICO-V3-02, 8 MB; partition table = factory table; OTA record selects factory app0; after esptool left the chip in download mode the new session restarted it: `BOOT CONFIRMED: flash boot, one start` |
| A-1 | Screen + backlight | **PASS** | owner: face visible, lit |
| A-2 | Upper button | **PASS** | owner: reacts |
| A-3 | Lower button | **PASS** | owner: reacts (bottom-left button steps through the factory apps) |
| A-4/5 | Touch on watch face | no reaction — **expected** | LILYGO factory source: watch faces do not read touch |
| A-4b | Touch in factory "Touch" tool (polls CST816S over I²C, RST IO33 / INT IO32 — same pins as Stage 1) | **FAIL — no reaction** | owner reached the Touch screen; touching/dragging changed nothing |
| A-6 | Normal restarts ×3 + banner | **PASS** | 3/3 `BOOT CONFIRMED`; ROM `boot:0x13 (SPI_FAST_FLASH_BOOT)`, DIO, factory `osw_config` lines, no Cyclift marker |
| A-7 | USB reconnection ×3 | **PASS** | owner: face returned all 3 times; scripted restart afterwards `BOOT CONFIRMED` |
| A-8 | Serial stability | **PASS** (45 s) | 105 bytes, 0 unexpected restarts after a confirmed boot |
| A-9 | End state | **PASS** | screen was off at the check = factory display timeout; one button press woke the face. Factory firmware active. |

## Conclusions
* The restart and boot-confirmation logic works with the real CH9102 adapter: 6 scripted restarts, 6 confirmed, including
  one directly after esptool had left the chip in download mode (the exact failure of the first install).
* Display, backlight, both buttons, USB reconnection, restarts: working on the factory firmware.
* **Touch does not respond under the factory firmware either.** Two independent firmwares (factory and Stage 1) with the same
  touch pins see no touch → most likely a hardware issue (touch flex cable/connector, or the touch controller), not Cyclift code.
  One "swipe U" event during the Stage 1 run remains unexplained (possibly a brief contact or noise). Not proven: the
  factory app's detection bug (`if (data = 0xB4)`) means it does not report a missing controller.
* Known side note: the factory firmware turns the display off after a timeout; a black screen with the firmware running is
  normal for it — test steps must wake it with a button before judging the screen.

## Remaining risks
* Touch hardware fault (open). Stage 1 touch tests (V2-5/V2-6) would fail for the same reason.
* Board revision V1.0 vs V1.1 still open (interrupt routing only).
* Restart logic proven for the normal cases only; USB loss mid-write is still handled only by "BOOT NOT CONFIRMED → stop".
