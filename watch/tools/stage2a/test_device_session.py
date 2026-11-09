#!/usr/bin/env python3
"""Regression tests for device_session.py and the Stage 1 install/recovery runners (no hardware; fake watch).

Background: on 9 Nov 2026 the install scripts left the ESP32 in ROM download mode (black screen until USB was re-plugged).
These tests simulate the watch at the level the scripts see it: esptool commands (which always leave the chip in download
mode), the serial port (RTS pulse = EN reset with IO0 high) and the ROM boot banner, plus injected failures.
"""
import os, sys, tempfile, types, argparse, random

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import device_session as ds

FAILS = []


def check(cond, msg):
    print(('ok   ' if cond else 'FAIL ') + msg)
    if not cond:
        FAILS.append(msg)


FLASH_BOOT = "ets Jul 29 2019 12:21:46\r\n\r\nrst:0x1 (POWERON_RESET),boot:0x13 (SPI_FAST_FLASH_BOOT)\r\nentry 0x40080400\r\n"
DL_BOOT = "ets Jul 29 2019 12:21:46\r\n\r\nrst:0x1 (POWERON_RESET),boot:0x3 (DOWNLOAD_BOOT(UART0/UART1/SDIO_REI_REO_V2))\r\nwaiting for download\r\n"
CYCLIFT = "Cyclift v3 proof of concept"


class FakeChip:
    def __init__(self, firmware="OSW factory\r\n"):
        self.mode = "running"            # running | download | off
        self.firmware = firmware
        self.faults = set()
        self.esptool_calls = 0


class FakeSerial:
    def __init__(self, chip, clock):
        self.chip, self.clock, self._rts, self.dtr, self.out, self.written = chip, clock, False, False, b"", b""

    @property
    def rts(self):
        return self._rts

    @rts.setter
    def rts(self, v):
        if self._rts and not v and not self.dtr:          # EN released with IO0 high -> chip restarts
            self._boot()
        self._rts = v

    def _boot(self):
        f = self.chip.faults
        if "dead" in f:
            self.chip.mode = "off"; return
        if "io0_stuck" in f:
            self.chip.mode = "download"; self.out += DL_BOOT.encode(); return
        if "bootloop" in f:
            self.chip.mode = "running"; self.out += (FLASH_BOOT + "abort()\r\n") .encode() * 3; return
        self.chip.mode = "running"
        self.out += (FLASH_BOOT + self.chip.firmware).encode()

    def read(self, n):
        self.clock.t += 0.5
        if "read_error" in self.chip.faults:
            raise OSError("ClearCommError failed (device disconnected)")
        chunk, self.out = self.out[:n], self.out[n:]
        return chunk

    def write(self, b):
        self.written += b

    def close(self):
        pass


class Clock:
    t = 0.0


class FakeTransport:
    def __init__(self, chip):
        self.chip, self.clock, self.calls = chip, Clock(), []

    def esptool(self, args, timeout=900):
        c = self.chip
        c.esptool_calls += 1
        self.calls.append(args[0])
        if "esptool_dies" in c.faults:
            c.mode = "download"                       # interrupted after the chip entered download mode
            raise ds.CommError("esptool did not complete: A fatal error occurred: The chip stopped responding")
        if "dead" in c.faults:
            return 2, "A fatal error occurred: Failed to connect to ESP32: No serial data received."
        c.mode = "download"                           # --before default_reset; --after no_reset
        cmd = args[0]
        if cmd == "write_flash":
            n = sum(1 for a in args if a.startswith("0x"))
            return 0, "Hash of data verified.\n" * n + "Leaving...\nStaying in bootloader."
        if cmd == "verify_flash":
            n = sum(1 for a in args if a.startswith("0x"))
            if "verify_fail" in c.faults:
                return 2, "-- verify FAILED (digest mismatch)\n"
            return 0, "-- verify OK (digest matched)\n" * n
        if cmd == "read_flash":
            open(args[3], "wb").write(b"\xff" * int(args[2], 16))
            return 0, "Read %d bytes" % int(args[2], 16)
        if cmd == "flash_id":
            return 0, "Chip is ESP32-PICO-V3-02 (revision v3.1)\nDetected flash size: 8MB\n"
        return 0, ""

    def open_serial(self):
        if "port_open" in self.chip.faults:
            raise OSError("could not open port 'COM4': PermissionError(13, 'Access is denied.')")
        return FakeSerial(self.chip, self.clock)

    def now(self):
        return self.clock.t

    def sleep(self, s):
        self.clock.t += s


def new(firmware="OSW factory\r\n", faults=()):
    chip = FakeChip(firmware)
    chip.faults = set(faults)
    logs = []
    sess = ds.DeviceSession(FakeTransport(chip), log=logs.append, boot_window=6)
    return chip, sess, logs


class Stop(Exception):
    pass


def must(ok, msg):
    if not ok:
        raise Stop(msg)


tmp = tempfile.mkdtemp()
fw = os.path.join(tmp, "fw.bin"); open(fw, "wb").write(b"x")

# 1 install + restart ---------------------------------------------------------------------------------------------------
chip, s, logs = new(firmware=CYCLIFT + "\r\n")
r = ds.run_phase(s, "install", lambda: (must(s.write([(0x400000, fw)]), "w"), must(s.verify([(0x400000, fw)]), "v")),
                 expect=CYCLIFT, stop_exc=(Stop,))
check(r.ok and chip.mode == "running", "install + restart: work passed, boot confirmed, chip left running")
i_v = next(i for i, l in enumerate(logs) if l.startswith("FLASH VERIFIED"))
i_b = next(i for i, l in enumerate(logs) if l.startswith("BOOT CONFIRMED"))
check(i_v < i_b, "install: 'FLASH VERIFIED' and 'BOOT CONFIRMED' are separate results, flash first")

# 2 read-only verification + restart -----------------------------------------------------------------------------------
chip, s, logs = new()
r = ds.run_phase(s, "verify-only", lambda: must(s.verify([(0x1000, fw)]), "v"), stop_exc=(Stop,))
check(r.ok and chip.mode == "running" and chip.esptool_calls == 1, "read-only verification + restart: chip left running")
chip, s, logs = new()
r = ds.run_phase(s, "read", lambda: s.read(0x9000, 0x5000, os.path.join(tmp, "n.bin")), stop_exc=(Stop,))
check(r.ok and chip.mode == "running", "read_flash + restart: chip left running")

# 3 verification failure + cleanup -------------------------------------------------------------------------------------
chip, s, logs = new(faults={"verify_fail"})
r = ds.run_phase(s, "p1", lambda: must(s.verify([(0x400000, fw)]), "verify failed"), stop_exc=(Stop,))
check(not r.ok and not r.work_ok and r.stop_reason == "verify failed", "verify failure: phase NOT passed, reason kept")
check(chip.mode == "running" and r.boot.confirmed, "verify failure: cleanup restarted the chip (not left in download mode)")
check(any("FLASH VERIFY FAILED" in l for l in logs) and any("NOT PASSED" in l for l in logs), "verify failure: log says VERIFY FAILED and NOT PASSED")

# 4 interrupted communication ------------------------------------------------------------------------------------------
chip, s, logs = new(faults={"esptool_dies"})
try:
    ds.run_phase(s, "p2", lambda: s.write([(0x1000, fw)]), stop_exc=(Stop,))
    check(False, "interrupted esptool: error must propagate")
except ds.CommError as e:
    check("stopped responding" in str(e), "interrupted esptool: ORIGINAL error propagates (not the cleanup's)")
check(chip.mode == "running", "interrupted esptool: cleanup restart attempted and the chip runs again")
check(any("ERROR CommError" in l for l in logs), "interrupted esptool: original error logged before cleanup")

# 4b interrupted + the port is gone too: original error still wins, boot reported NOT confirmed
chip, s, logs = new(faults={"esptool_dies", "port_open"})
try:
    ds.run_phase(s, "p2", lambda: s.write([(0x1000, fw)]), stop_exc=(Stop,)); check(False, "must raise")
except ds.CommError:
    check(True, "USB gone: original CommError propagates although the cleanup also failed")
check(any("BOOT NOT CONFIRMED" in l or "NOT confirmed" in l for l in logs) and any(l.startswith("STOP:") for l in logs),
      "USB gone: log says the boot is NOT confirmed and tells the user to stop")
check(not any(l.startswith("BOOT CONFIRMED") for l in logs), "USB gone: never reports BOOT CONFIRMED")

# 5 serial-port exceptions ---------------------------------------------------------------------------------------------
for fault, label in (("port_open", "port cannot be opened"), ("read_error", "read error during boot check")):
    chip, s, logs = new(faults={fault})
    b = s.restart_and_confirm()
    check(not b.confirmed and s.state != "running", "serial exception (%s): returns NOT confirmed, does not raise" % label)
    r = ds.run_phase(s, "x", lambda: None)
    check(not r.ok and r.work_ok, "serial exception (%s): phase reports work passed but phase NOT passed" % label)

# 6 boot-confirmation timeout and wrong boots ---------------------------------------------------------------------------
cases = [({"dead"}, None, "no output"), ({"io0_stuck"}, None, "download mode"), ({"bootloop"}, None, "starts"),
         (set(), CYCLIFT, "not seen")]
for faults, expect, why in cases:
    chip, s, logs = new(faults=faults)
    b = s.restart_and_confirm(expect=expect)
    check(not b.confirmed and why in b.reason, "boot check rejects: %s -> %s" % (sorted(faults) or "factory firmware", b.reason))
chip, s, logs = new(firmware=CYCLIFT + "\r\n")
check(not s.restart_and_confirm(forbid=CYCLIFT).confirmed, "boot check rejects the wrong firmware (forbid marker)")
chip, s, logs = new()
t0 = s.t.now(); s.restart_and_confirm(window=6)
check(s.t.now() - t0 <= 7.5, "boot check ends after its time limit")

# 7 monitoring only in normal execution ----------------------------------------------------------------------------------
chip, s, logs = new()
s.verify([(0x1000, fw)])
try:
    s.listen(5); check(False, "listen in download mode must be refused")
except ds.NotRunning:
    check(True, "serial monitoring refused while the chip is in download mode")
s.restart_and_confirm()
s.t.chip.firmware = ""
check(isinstance(s.listen(3, send="u"), str), "serial monitoring allowed after the boot was confirmed")

# 8 repeated runs never leave the chip in programming mode ---------------------------------------------------------------
rnd = random.Random(7)
ok_all = True
for i in range(40):
    fault = rnd.choice([None, None, "verify_fail", "esptool_dies"])
    chip, s, logs = new(faults={fault} if fault else set())
    try:
        ds.run_phase(s, "run%d" % i, lambda: must(s.verify([(0x1000, fw)]), "v"), stop_exc=(Stop,))
    except ds.CommError:
        pass
    ok_all &= chip.mode == "running" and s.state == "running"
check(ok_all, "40 repeated runs (pass / verify failure / interrupted): chip never left in download mode")
chip, s, logs = new()
for i in range(5):
    ds.run_phase(s, "same-session-%d" % i, lambda: s.verify([(0x1000, fw)]))
check(chip.mode == "running", "5 consecutive phases in one session: chip ends running")

# 9 no error path reports a successful boot -----------------------------------------------------------------------------
false_ok = []
for faults in ({"dead"}, {"io0_stuck"}, {"bootloop"}, {"port_open"}, {"read_error"}, {"esptool_dies", "port_open"}):
    chip, s, logs = new(faults=faults)
    try:
        r = ds.run_phase(s, "f", lambda: s.verify([(0x1000, fw)]), stop_exc=(Stop,))
        if r.ok or r.boot.confirmed:
            false_ok.append(sorted(faults))
    except ds.CommError:
        pass
    if any(l.startswith("BOOT CONFIRMED") for l in logs) or any("PASSED (work passed, firmware start confirmed)" in l for l in logs):
        false_ok.append(sorted(faults))
check(not false_ok, "no failure path reports BOOT CONFIRMED or PHASE PASSED (%s)" % false_ok)

# 10 cleanup cannot conceal the original error ---------------------------------------------------------------------------
chip, s, logs = new()
s.restart_and_confirm = lambda **k: (_ for _ in ()).throw(RuntimeError("cleanup exploded"))
try:
    ds.run_phase(s, "z", lambda: (_ for _ in ()).throw(ValueError("original problem"))); check(False, "must raise")
except ValueError:
    check(True, "a failing cleanup never replaces the original error")
except RuntimeError:
    check(False, "cleanup error replaced the original error")
chip, s, logs = new()
try:
    with s:
        s.verify([(0x1000, fw)]); raise KeyError("boom")
except KeyError:
    check(chip.mode == "running", "context manager: exception propagates and the chip is restarted")

# 11 the real runners use only the session (static check: no direct esptool/serial access, no 'no_reset') -------------------
for f in ("pc_install_runner.py", "pc_recovery_b_runner.py"):
    src = open(os.path.join(HERE, f), encoding="utf-8").read()
    check("subprocess" not in src and "serial.Serial" not in src and "no_reset" not in src,
          "%s: no direct esptool/serial calls (all through DeviceSession)" % f)

# 12 installer runner end-to-end with the fake watch (recovery R-A, checkpoint phase, error phase) ------------------------
priv = tempfile.mkdtemp(); os.makedirs(os.path.join(priv, "plan_pieces"))
for tag in ("original", "planned"):
    for off in (0x1000, 0x5000, 0x8000, 0xF000):
        open(os.path.join(priv, "plan_pieces", "%s_0x%06x.bin" % (tag, off)), "wb").write(b"\xff" * 0x1000)
os.environ["CY_PRIVATE_DIR"] = priv; os.environ["CY_TOOLS_DIR"] = HERE
g = {"__file__": os.path.join(HERE, "pc_install_runner.py"), "__name__": "cy_install"}
exec(compile(open(os.path.join(HERE, "pc_install_runner.py"), encoding="utf-8").read(), "cy_install", "exec"), g)
chip = FakeChip(); fake = FakeTransport(chip)
g["S"] = ds.DeviceSession(fake, log=lambda m: g["log"](m), boot_window=6)
check(g["recovery"]("RA") is True and chip.mode == "running", "runner: recovery R-A writes, verifies, restarts, confirms factory start")
chip.faults = {"verify_fail"}
check(g["recovery"]("RA") is False and chip.mode == "running", "runner: recovery with a verify failure returns False and still restarts")
chip.faults = set(); chip.firmware = CYCLIFT + "\r\n"
g["_t_ok"] = lambda: g["_checkpoint"](False, "T")
check(g["phase"]("t_ok") is True, "runner: a checkpoint phase passes with one confirmed start")
chip.faults = {"bootloop"}
check(g["phase"]("t_ok") is False, "runner: a reset loop at a checkpoint fails the phase")
chip.faults = {"dead"}
check(g["phase"]("t_ok") is False, "runner: no boot output fails the phase (boot not confirmed)")
log_txt = open(os.path.join(priv, "install_log.txt"), encoding="utf-8").read()
check("STOP: the watch could not be confirmed running" in log_txt, "runner log tells the owner to stop when the boot is not confirmed")

# 13 read-only identification tool: final boot check on success and on error -------------------------------------------------
import stage2a_readonly as ro
chip, s, logs = new()
outdir = tempfile.mkdtemp()


def fake_runner(cmd, **k):
    raise RuntimeError("esptool flash_id failed (exit 2)")


ro_cmd = ro.cmd_identify
ro.cmd_identify = lambda a, runner=None: fake_runner(None)
try:
    ro.main(["identify", "--port", "COM4", "--out", outdir], session_factory=lambda: s)
    check(False, "identify error must propagate")
except RuntimeError as e:
    check("flash_id failed" in str(e) and chip.mode == "running", "read-only tool: original error kept, watch restarted")
ro.cmd_identify = lambda a, runner=None: None
chip.faults = {"dead"}
rc = ro.main(["identify", "--port", "COM4", "--out", outdir], session_factory=lambda: s)
check(rc == 4, "read-only tool: exit code 4 when the boot cannot be confirmed")
ro.cmd_identify = ro_cmd

print("device session: %d failures" % len(FAILS))
sys.exit(1 if FAILS else 0)
