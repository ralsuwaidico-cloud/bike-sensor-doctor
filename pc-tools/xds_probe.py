#!/usr/bin/env python3
r"""
XDS / Branta power-meter Bluetooth probe  (Windows / macOS / Linux, via Bleak)

Purpose: talk to XDS-A001-9769 directly from a PC to find the reliable connection
sequence and confirm power/cadence decoding, without Android's reconnect quirks.

It is READ-ONLY and safe: it scans, connects, discovers services, subscribes to
notifications, and logs raw bytes. It NEVER writes to the sensor (no control-point
writes, no firmware, no calibration). It also stress-tests connect/disconnect to
reproduce the "three failed attempts" seen on the phone.

You do nothing but run it and pedal when asked. It writes a full JSON log to
    <Documents>\bike_probe\xds_probe_<timestamp>.json   (Windows)
    ~/bike_probe/xds_probe_<timestamp>.json             (mac/Linux)
so the results can be analysed exactly.

Run:  python xds_probe.py
"""
import asyncio, json, os, sys, time, platform, subprocess
from pathlib import Path

# ---- self-install bleak if missing -------------------------------------------
try:
    from bleak import BleakScanner, BleakClient
    from bleak.exc import BleakError
except ModuleNotFoundError:
    print("Installing the Bluetooth library (bleak)… one moment.")
    subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "bleak"], check=False)
    from bleak import BleakScanner, BleakClient
    from bleak.exc import BleakError

TARGET_NAME = "XDS-A001-9769"
TARGET_ADDR_HINT = "C0:A1:25:07:97:69"     # Windows hides the MAC; matched when visible

S_1828 = "00001828-0000-1000-8000-00805f9b34fb"   # XDS data service (SIG "Mesh Proxy")
C_2A63 = "00002a63-0000-1000-8000-00805f9b34fb"   # 11-byte power/cadence packet
C_2A55 = "00002a55-0000-1000-8000-00805f9b34fb"   # control point (we never write)
C_2A19 = "00002a19-0000-1000-8000-00805f9b34fb"   # battery
A_0202 = "a6ed0202-d344-460a-8075-b9e8ec90d71b"   # vendor telemetry (~7.5 Hz)
A_0402 = "a6ed0402-d344-460a-8075-b9e8ec90d71b"   # vendor
DIS = {
    "00002a24-0000-1000-8000-00805f9b34fb": "model",
    "00002a25-0000-1000-8000-00805f9b34fb": "serial",
    "00002a26-0000-1000-8000-00805f9b34fb": "firmware",
    "00002a27-0000-1000-8000-00805f9b34fb": "hardware",
    "00002a28-0000-1000-8000-00805f9b34fb": "software",
}

NOTIFY_TARGETS = [C_2A63, A_0202, A_0402, C_2A19]

log = {
    "tool": "xds_probe",
    "version": 1,
    "started_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    "platform": f"{platform.system()} {platform.release()} py{platform.python_version()} bleak-ok",
    "events": [],
    "scan": [],
    "device_info": {},
    "services": [],
    "connect_attempts": [],
    "notifications": {},   # uuid -> list of {t_ms, hex}
    "phases": {},          # "stationary"/"pedaling" -> {uuid: count}
    "summary": {},
}

def ev(kind, **kw):
    e = {"t": round(time.time(), 3), "kind": kind, **kw}
    log["events"].append(e)
    msg = kw.get("msg", "")
    print(f"[{time.strftime('%H:%M:%S')}] {kind}: {msg}")

def hexs(b): return " ".join(f"{x:02X}" for x in bytes(b))

def s16(b, i):
    v = b[i] | (b[i+1] << 8)
    return v - 65536 if v >= 32768 else v
def u16(b, i): return b[i] | (b[i+1] << 8)

def decode_2a63(b):
    if len(b) < 11: return None
    cad = s16(b, 6)
    return {"power_w": u16(b, 0), "left_w": s16(b, 2), "right_w": s16(b, 4),
            "cadence_signed": cad, "cadence_rpm": abs(cad), "backwards": cad < 0,
            "angle_deg": u16(b, 8), "error": b[10]}

# --------------------------------------------------------------------------- scan
async def scan(timeout=20):
    ev("scan_start", msg=f"scanning {timeout}s for {TARGET_NAME} … spin the pedals a few times to wake the sensor")
    found = {}
    def cb(d, adv):
        found[d.address] = (d, adv)
    scanner = BleakScanner(detection_callback=cb)
    await scanner.start(); await asyncio.sleep(timeout); await scanner.stop()
    target = None
    for addr, (d, adv) in found.items():
        name = adv.local_name or d.name
        entry = {"address": addr, "name": name, "rssi": adv.rssi,
                 "services": list(adv.service_uuids or [])}
        log["scan"].append(entry)
        hit = (name == TARGET_NAME) or (addr.upper() == TARGET_ADDR_HINT) or \
              (S_1828 in [s.lower() for s in (adv.service_uuids or [])])
        if hit and target is None:
            target = d
            ev("scan_hit", msg=f"found {name or addr} @ {adv.rssi} dBm, services={entry['services']}")
    if target is None:
        ev("scan_miss", msg=f"{TARGET_NAME} not seen ({len(found)} other devices). Is it awake / in range?")
    return target

# ------------------------------------------------------------------- one attempt
async def attempt_connect(device, label, timeout, pre_delay=0.0):
    """Returns (client_or_None, info dict). Caller disconnects."""
    info = {"label": label, "timeout": timeout, "pre_delay": pre_delay,
            "connected": False, "services_ok": False, "first_packet_ms": None, "error": None}
    if pre_delay: await asyncio.sleep(pre_delay)
    t0 = time.time()
    first_packet = {"t": None}

    def on_notify(_char, data):
        if first_packet["t"] is None:
            first_packet["t"] = time.time()

    client = BleakClient(device, timeout=timeout)
    try:
        ev("connect_try", msg=f"[{label}] connecting (timeout {timeout}s)…")
        await client.connect()
        info["connected"] = client.is_connected
        info["connect_ms"] = round((time.time() - t0) * 1000)
        ev("connect_ok", msg=f"[{label}] link up in {info['connect_ms']} ms")
        # services
        svcs = client.services
        info["services_ok"] = any(s.uuid.lower() == S_1828 for s in svcs)
        # subscribe to 0x2A63 to prove data actually flows
        has_2a63 = any(c.uuid.lower() == C_2A63 for s in svcs for c in s.characteristics)
        if has_2a63:
            await client.start_notify(C_2A63, on_notify)
            # wait up to 4 s for the first packet (sensor streams ~1 Hz)
            for _ in range(40):
                if first_packet["t"]: break
                await asyncio.sleep(0.1)
            if first_packet["t"]:
                info["first_packet_ms"] = round((first_packet["t"] - t0) * 1000)
                ev("data_ok", msg=f"[{label}] first packet {info['first_packet_ms']} ms after connect")
            else:
                ev("data_none", msg=f"[{label}] connected + discovered but NO packet within 4 s")
            await client.stop_notify(C_2A63)
        else:
            ev("no_2a63", msg=f"[{label}] 0x2A63 not present under services")
        return client, info
    except Exception as e:
        info["error"] = f"{type(e).__name__}: {e}"
        ev("connect_fail", msg=f"[{label}] {info['error']}")
        try: await client.disconnect()
        except Exception: pass
        return None, info
    finally:
        log["connect_attempts"].append(info)

# ----------------------------------------------------- investigate the failure
async def investigate(device):
    """Reproduce the phone's 'three failed attempts' and find a sequence that works."""
    ev("investigate", msg="testing connection strategies (reproduces the phone's failure pattern)")
    strategies = [
        ("A: default 20s",            20, 0.0),
        ("B: retry +2s settle",       20, 2.0),
        ("C: long 30s timeout",       30, 1.0),
    ]
    good = None
    for label, to, pre in strategies:
        client, info = await attempt_connect(device, label, to, pre)
        if client:
            if info["first_packet_ms"] is not None and good is None:
                good = info
            await client.disconnect()
            ev("disconnect", msg=f"[{label}] clean disconnect; settling 3 s")
            await asyncio.sleep(3.0)   # KEY: let the stack fully release before the next connect
        else:
            await asyncio.sleep(3.0)
    # rapid reconnect stress: 5 quick cycles to see if error 133-style failures appear
    ev("stress", msg="rapid reconnect stress test (5 cycles)")
    cyc = []
    for i in range(5):
        client, info = await attempt_connect(device, f"stress#{i+1}", 20, 0.0)
        ok = bool(client and info["first_packet_ms"] is not None)
        cyc.append({"cycle": i+1, "ok": ok, "error": info["error"], "connect_ms": info.get("connect_ms")})
        if client: await client.disconnect()
        await asyncio.sleep(1.5)
    log["summary"]["stress_cycles"] = cyc
    log["summary"]["stress_success"] = sum(1 for c in cyc if c["ok"])
    return good

# ------------------------------------------------------- capture a live session
async def capture(device):
    ev("session", msg="opening the measurement session")
    client = BleakClient(device, timeout=30)
    await client.connect()
    # read device info
    for uuid, key in DIS.items():
        try:
            v = await client.read_gatt_char(uuid)
            try: log["device_info"][key] = bytes(v).decode("utf-8", "ignore").strip("\x00").strip()
            except Exception: log["device_info"][key] = hexs(v)
        except Exception: pass
    try:
        bat = await client.read_gatt_char(C_2A19)
        log["device_info"]["battery_pct"] = bat[0]
    except Exception: pass
    # record full service table
    for s in client.services:
        log["services"].append({"service": s.uuid, "chars": [
            {"uuid": c.uuid, "props": c.properties} for c in s.characteristics]})
    ev("device", msg=f"{log['device_info']}")

    t0 = time.time()
    for uuid in NOTIFY_TARGETS:
        present = any(c.uuid.lower() == uuid for s in client.services for c in s.characteristics)
        if not present: continue
        log["notifications"].setdefault(uuid, [])
        def make(u):
            def h(_c, data):
                log["notifications"][u].append({"t_ms": round((time.time()-t0)*1000), "hex": hexs(data)})
            return h
        try:
            await client.start_notify(uuid, make(uuid))
            ev("subscribed", msg=f"subscribed {uuid}")
        except Exception as e:
            ev("subscribe_fail", msg=f"{uuid}: {e}")

    async def phase(name, seconds, prompt):
        print("\n" + "="*60 + f"\n{prompt}\n" + "="*60)
        start = {u: len(v) for u, v in log["notifications"].items()}
        for s in range(seconds, 0, -1):
            print(f"  {name}: {s:>2}s ", end="\r"); await asyncio.sleep(1)
        print()
        counts = {u: len(log["notifications"][u]) - start.get(u, 0) for u in log["notifications"]}
        log["phases"][name] = counts
        # decode most recent 2a63 in this phase
        dec = None
        if log["notifications"].get(C_2A63):
            last = log["notifications"][C_2A63][-1]["hex"]
            dec = decode_2a63(bytes(int(x,16) for x in last.split()))
        ev("phase_done", msg=f"{name}: {counts}  last_2a63={dec}")

    await phase("stationary", 15, "KEEP THE BIKE STILL for 15 seconds (do not touch the pedals).")
    await phase("pedaling", 30, "PEDAL FORWARDS steadily (~80 rpm) for 30 seconds. Push with some force.")

    for uuid in list(log["notifications"].keys()):
        try: await client.stop_notify(uuid)
        except Exception: pass
    await client.disconnect()
    ev("session_end", msg="session closed")

# --------------------------------------------------------------- analysis/output
def analyse():
    s = log["summary"]
    atts = log["connect_attempts"]
    s["attempts_total"] = len(atts)
    s["attempts_connected"] = sum(1 for a in atts if a["connected"])
    s["attempts_with_data"] = sum(1 for a in atts if a["first_packet_ms"] is not None)
    # decode all 2a63 packets, split by phase using timestamps is complex; just summarise
    p = [decode_2a63(bytes(int(x,16) for x in n["hex"].split()))
         for n in log["notifications"].get(C_2A63, [])]
    p = [d for d in p if d]
    if p:
        rotating = [d for d in p if d["cadence_rpm"] > 0]
        powered = [d for d in rotating if d["power_w"] >= 20 and not d["backwards"]]
        s["packets_2a63"] = len(p)
        s["rotating_packets"] = len(rotating)
        s["max_cadence"] = max((d["cadence_rpm"] for d in p), default=0)
        s["any_backwards"] = any(d["backwards"] for d in rotating)
        s["max_power_w"] = max((d["power_w"] for d in p), default=0)
        s["powered_packets"] = len(powered)
        s["power_verified_under_load"] = len(powered) >= 5

def save():
    if platform.system() == "Windows":
        base = Path(os.path.expanduser("~")) / "Documents" / "bike_probe"
    else:
        base = Path(os.path.expanduser("~")) / "bike_probe"
    base.mkdir(parents=True, exist_ok=True)
    f = base / f"xds_probe_{time.strftime('%Y%m%d_%H%M%S')}.json"
    f.write_text(json.dumps(log, indent=2))
    print("\n" + "#"*60)
    print(f"# RESULTS SAVED:\n#   {f}")
    print("#"*60)
    print("Summary:", json.dumps(log["summary"], indent=2))
    return f

async def main():
    ev("boot", msg=f"xds_probe on {log['platform']}")
    dev = await scan(20)
    if not dev:
        ev("abort", msg="sensor not found — cannot continue")
        save(); return
    await investigate(dev)
    await asyncio.sleep(2)
    try:
        await capture(dev)
    except Exception as e:
        ev("capture_error", msg=f"{type(e).__name__}: {e}")
    analyse()
    save()
    print("\nDone. Share the saved JSON file (or tell Claude the folder) so it can analyse the results.")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nStopped by user."); save()
    input("\nPress Enter to close this window…")
