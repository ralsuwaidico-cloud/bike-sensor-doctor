#!/usr/bin/env python3
"""Safe ESP32 session for every script that talks to the Cyclift watch over the T-U2T (COM port).

Why: on 9 Nov 2026 the install and recovery scripts ended with `esptool ... --after no_reset` and left the chip in its ROM
download mode; no firmware ran and the screen stayed black until the owner re-plugged USB. This module makes the end state
explicit:

* every esptool command leaves the chip in download mode -> the session records state "download";
* `finish()` (normal completion) and the context-manager exit (any exception) pulse EN with IO0 high to start the firmware and
  then CONFIRM it from the ROM boot banner (`boot:0x13 (SPI_FAST_FLASH_BOOT)`, exactly one start, optional app marker);
* "flash verified" and "boot confirmed" are separate results and are logged with different words;
* serial listening without a reset is refused unless the boot was confirmed;
* a cleanup restart never hides the original error: the original exception always propagates, the cleanup result is logged;
* if the restart cannot be confirmed the session says so ("BOOT NOT CONFIRMED") and the caller must stop.
A restart cannot be guaranteed after every USB or hardware failure; the session only reports what it could confirm.
"""
import subprocess
import sys
import time

ROM_FLASH_BOOT = "SPI_FAST_FLASH_BOOT"
ROM_DOWNLOAD_BOOT = "DOWNLOAD_BOOT"


class CommError(Exception):
    """The watch could not be reached (esptool failed to start/finish, port error, timeout)."""


class NotRunning(Exception):
    """Serial monitoring was requested while the firmware is not confirmed running."""


class BootResult:
    def __init__(self, confirmed, reason, text="", starts=0):
        self.confirmed, self.reason, self.text, self.starts = confirmed, reason, text, starts

    def __repr__(self):
        return "BootResult(confirmed=%s, starts=%d, %s)" % (self.confirmed, self.starts, self.reason)


class RealTransport:
    """esptool through the current Python, reset/monitor through pyserial (DTR/RTS wiring of the T-U2T auto-reset)."""

    def __init__(self, port="COM4", baud="921600"):
        self.port, self.baud = port, baud

    def esptool(self, args, timeout=900):
        cmd = [sys.executable, "-m", "esptool", "--chip", "esp32", "--port", self.port, "--baud", self.baud,
               "--before", "default_reset", "--after", "no_reset"] + list(args)
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        except (subprocess.TimeoutExpired, OSError) as e:
            raise CommError("esptool did not complete: %s" % e)
        out = "\n".join(l for l in (r.stdout + r.stderr).splitlines() if not l.startswith("MAC"))
        return r.returncode, out

    def open_serial(self):
        import serial
        s = serial.Serial(); s.port = self.port; s.baudrate = 115200; s.timeout = 0.2; s.dtr = False; s.rts = False
        s.open()
        return s

    def now(self):
        return time.time()

    def sleep(self, seconds):
        time.sleep(seconds)


class DeviceSession:
    def __init__(self, transport, log=print, boot_window=12.0):
        self.t, self.log, self.boot_window = transport, log, boot_window
        self.state = "unknown"          # unknown | download | started-unconfirmed | running
        self.last_boot = None

    # ------------------------------------------------------------------ esptool (always ends in download mode)
    def esptool(self, args, timeout=900):
        self.state = "unknown"
        try:
            rc, out = self.t.esptool(list(args), timeout=timeout)
        except CommError:
            self.state = "unknown"
            raise
        self.state = "download" if rc == 0 else "unknown"
        return rc, out

    def write(self, pairs):
        args = ["write_flash", "--flash_mode", "keep", "--flash_freq", "keep", "--flash_size", "keep"]
        for off, f in pairs:
            args += [hex(off), f]
        rc, out = self.esptool(args)
        ok = rc == 0 and out.count("Hash of data verified") >= len(pairs)
        self.log("FLASH WRITE %s: %s" % ("OK" if ok else "FAILED", ", ".join(hex(o) for o, _ in pairs)))
        return ok

    def verify(self, pairs):
        args = ["verify_flash"]
        for off, f in pairs:
            args += [hex(off), f]
        rc, out = self.esptool(args)
        ok = rc == 0 and out.count("verify OK") >= len(pairs) and "verify FAILED" not in out
        self.log("FLASH %s: %s" % ("VERIFIED" if ok else "VERIFY FAILED", ", ".join(hex(o) for o, _ in pairs)))
        return ok

    def read(self, off, size, path):
        rc, out = self.esptool(["read_flash", hex(off), hex(size), path])
        if rc != 0:
            raise CommError("read_flash 0x%x failed" % off)
        return open(path, "rb").read()

    # ------------------------------------------------------------------ restart into the firmware and confirm it
    def restart_and_confirm(self, expect=None, forbid=None, window=None):
        window = self.boot_window if window is None else window
        try:
            s = self.t.open_serial()
        except Exception as e:                      # serial.SerialException, OSError, …
            self.state = "unknown"
            self.last_boot = BootResult(False, "serial port could not be opened: %s" % e)
            return self.last_boot
        buf = b""
        try:
            s.dtr = False; s.rts = True; self.t.sleep(0.12); s.rts = False          # EN pulse with IO0 high
            self.state = "started-unconfirmed"
            t0 = self.t.now()
            while self.t.now() - t0 < window:
                buf += s.read(4096)
        except Exception as e:
            self.last_boot = BootResult(False, "serial error during boot check: %s" % e, buf.decode("utf-8", "replace"))
            self.state = "unknown"
            return self.last_boot
        finally:
            try:
                s.close()
            except Exception:
                pass
        txt = buf.decode("utf-8", "replace")
        starts = txt.count("rst:0x") - txt.count("rst:0x5 ")          # deep-sleep wake-ups are not restarts
        if not txt.strip():
            r = BootResult(False, "no output within %.0f s (boot not confirmed)" % window, txt, 0)
        elif ROM_DOWNLOAD_BOOT in txt:
            r = BootResult(False, "chip started in download mode, not the firmware", txt, starts)
        elif ROM_FLASH_BOOT not in txt:
            r = BootResult(False, "no ROM flash-boot banner seen", txt, starts)
        elif starts != 1:
            r = BootResult(False, "%d starts in %.0f s (reset loop?)" % (starts, window), txt, starts)
        elif expect and expect not in txt:
            r = BootResult(False, "firmware marker %r not seen" % expect, txt, starts)
        elif forbid and forbid in txt:
            r = BootResult(False, "unexpected firmware marker %r seen" % forbid, txt, starts)
        else:
            r = BootResult(True, "flash boot, one start" + (", marker %r" % expect if expect else ""), txt, starts)
        self.state = "running" if r.confirmed else "started-unconfirmed"
        self.last_boot = r
        self.log("BOOT %s: %s" % ("CONFIRMED" if r.confirmed else "NOT CONFIRMED", r.reason))
        return r

    def listen(self, seconds, send=None):
        """Serial monitoring WITHOUT a reset; only allowed once the firmware is confirmed running.
        `send` (optional) is written once half-way (the Stage 1 test hook, e.g. 'u' = simulated swipe)."""
        if self.state != "running":
            raise NotRunning("refusing to monitor: firmware not confirmed running (state %s)" % self.state)
        s = self.t.open_serial()
        buf, sent = b"", False
        try:
            s.dtr = False; s.rts = False                                   # no reset, no download request
            t0 = self.t.now()
            while self.t.now() - t0 < seconds:
                buf += s.read(4096)
                if send and not sent and self.t.now() - t0 > seconds / 2:
                    s.write(send.encode()); sent = True
        except Exception:
            self.state = "unknown"
            raise
        finally:
            try:
                s.close()
            except Exception:
                pass
        return buf.decode("utf-8", "replace")

    def finish(self, expect=None, forbid=None):
        """Normal completion: leave the watch running its firmware and confirm it."""
        return self.restart_and_confirm(expect=expect, forbid=forbid)

    # ------------------------------------------------------------------ cleanup on errors
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        if exc_type is not None and self.state != "running":
            self.log("cleanup after error (%s: %s): attempting restart into the firmware" % (exc_type.__name__, exc))
            try:
                r = self.restart_and_confirm()
                self.log("cleanup result: %s" % ("firmware start confirmed" if r.confirmed else "NOT confirmed — " + r.reason))
            except Exception as e2:                 # never replace the original error
                self.log("cleanup restart failed: %s" % e2)
        return False                                # original exception always propagates


# ---------------------------------------------------------------------- one phase = work + mandatory final restart
class PhaseResult:
    def __init__(self, name):
        self.name, self.work_ok, self.stop_reason, self.error, self.boot = name, False, None, None, None

    @property
    def ok(self):
        return self.work_ok and self.boot is not None and self.boot.confirmed


def run_phase(session, name, fn, expect=None, forbid=None, stop_exc=()):
    """Run `fn()` and ALWAYS finish with a restart attempt + boot check.

    * work passed  -> restart, confirm with the phase's expected marker (expect/forbid);
    * planned stop (stop_exc) or unexpected error -> restart, confirm only that *a* firmware started (no marker);
    * an unexpected error is re-raised unchanged after the cleanup has been logged (cleanup never hides it);
    * the phase counts as OK only if the work passed AND the boot was confirmed.
    """
    log = session.log
    res = PhaseResult(name)
    log("===== PHASE %s =====" % name)
    try:
        fn()
        res.work_ok = True
        log("PHASE %s: work PASSED" % name)
    except stop_exc as e:
        res.stop_reason = str(e)
        log("PHASE %s: STOPPED: %s — no further writes" % (name, e))
    except BaseException as e:                      # includes KeyboardInterrupt / serial errors / CommError
        res.error = e
        log("PHASE %s: ERROR %s: %s" % (name, type(e).__name__, e))
    try:
        if res.work_ok and session.state == "running" and session.last_boot is not None and session.last_boot.confirmed \
                and not expect and not forbid:
            res.boot = session.last_boot            # already confirmed after the last device command
        else:
            res.boot = session.restart_and_confirm(expect=expect if res.work_ok else None,
                                                   forbid=forbid if res.work_ok else None)
    except BaseException as e2:
        res.boot = BootResult(False, "restart attempt raised %s: %s" % (type(e2).__name__, e2))
        log("BOOT NOT CONFIRMED: %s" % res.boot.reason)
    if res.ok:
        log("===== PHASE %s PASSED (work passed, firmware start confirmed) =====" % name)
    else:
        log("***** PHASE %s NOT PASSED: work %s; firmware start %s. *****" % (
            name, "passed" if res.work_ok else "did NOT pass",
            "confirmed" if res.boot.confirmed else "NOT confirmed (" + res.boot.reason + ")"))
        if not res.boot.confirmed:
            log("STOP: the watch could not be confirmed running its firmware. Do not continue. "
                "Disconnect and reconnect USB, note what the screen shows, and report it.")
    if res.error is not None:
        raise res.error                             # the ORIGINAL error, not the cleanup's
    return res
