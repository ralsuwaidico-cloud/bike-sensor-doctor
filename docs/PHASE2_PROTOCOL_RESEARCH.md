# Phase 2 — XDS / Branta power meter protocol research

Research date: 2026-10-11. Sources are listed per item; confidence is stated per item. **No byte sequences in this
document were invented — every one is quoted from the linked open-source project.**

## 1. Is XDS-A001-9769 the power meter?

**Very likely yes (high confidence).** Three independent open-source projects that bridge XDS/Branta meters to
Garmin/ANT+ describe the same fingerprint your phone sees:

- They filter on **service UUID 0x1828 in the advertisement** (not 0x1818/0x1816).
- One bridge's README logs a different unit as `C0:A1:25:04:32:08 … 匹配功率计` ("matched power meter") — same
  `C0:A1:25` MAC prefix as yours.
- The MAC prefix `C0:A1:25` is **not registered** in the IEEE OUI database (maclookup.app returns not-found), which is
  typical for small-vendor Nordic-chip firmware using a self-assigned address.
- The official Branta page states the chip platform is Nordic ("Nordic Next-Generation Wireless Silicon") and never
  mentions ANT+ or Bluetooth Cycling Power.

Sources:
- https://xds.co/pages/branta
- https://github.com/DuoDuoJuZi/xds_forwarding (nRF52832, BLE → ANT+)
- https://github.com/66ccff231/ad350-nrf52840-bridge and https://github.com/66ccff231/xds-nrf52840-bridge (nRF52840, BLE → standard 0x1818)
- https://github.com/MashiroKanon15684/XDS_AllInOne (nRF52840, BLE → ANT+)

The app's Scan tab flags any device matching name `XDS*`, MAC `C0:A1:25*` or advertised 0x1828 as "XDS-like", and the
RSSI near/far test is the remaining physical confirmation (hold the phone at the crank, then walk 3 m away).

## 2. Why the Garmin Edge 820 cannot see it

**Confirmed by design (high confidence).** The meter does not expose the standard Cycling Power service 0x1818, CSC
0x1816, or ANT+. Garmin only pairs sensors that advertise those. Chinese reviews state the meter's data is
"仅支持品牌APP" (only supported by the brand's own app). A retailer listing claiming "ANT+ and Bluetooth Smart" appears to
be boilerplate and is contradicted by the three bridge projects, all of which exist precisely because the meter is
Garmin-incompatible.

Sources: https://post.smzdm.com/p/a74mkowl , https://post.smzdm.com/p/an5v4zxp , https://powermetercity.com/?p=177644 (conflicting claim)

## 3. The official app

- **X-LAB Bikes** (in-app: "X-LAB Connect"), developer Carbon Catalyst Inc.
  - Android: `com.xds.ebike.intl` — https://play.google.com/store/apps/details?id=com.xds.ebike.intl
  - iOS: https://apps.apple.com/us/app/x-lab-bikes/id6749517038
  - Listing promises: track power metrics, calibrate power meter, updates and diagnostics.
- In China: 喜德盛APP.

**This is the single most important next test**: if X-LAB Bikes shows live power on your Nokia, the sensor is
healthy and the whole problem is protocol compatibility. If it does not, the fault is in the sensor (or its pairing
state), not in your phone or Garmin.

## 4. What the community found about the data path (verbatim, with source)

From `xds_ble_bridge.c` and `xds_protocol.c` in https://github.com/DuoDuoJuZi/xds_forwarding:

| Step | What the bridge does |
|---|---|
| Scan filter | 16-bit service UUID `0x1828` in advertising data |
| Service | `0x1828` |
| Measurement characteristic | `0x2A63` (notify) — **inside 0x1828**, not inside 0x1818 |
| Control characteristic | `0x2A55` (write) |
| Sequence | discover 0x1828 → characteristics → write `{0x01,0x00}` to CCCD of 0x2A63 → wait 800 ms → write `{0x02, 0x16, 0xAA, 0x10}` to 0x2A55 (write request), retry every 2000 ms up to 5× → disconnect if no packet for 30 s |
| Payload | 11 bytes little-endian: [0-1] total power u16 W, [2-3] left s16, [4-5] right s16, [6-7] cadence s16 rpm (negative → 0), [8-9] crank angle u16 °, [10] error u8 |

From the README of https://github.com/66ccff231/ad350-nrf52840-bridge (translated): "the other open-source
implementation writes `02 16 AA 10` to the control point, but in practice this device returns `0x81` and rejects it";
their unit **streamed on 0x2A63 without any start command**.

So the community evidence is split: one unit needed the write, one rejected it harmlessly and streamed anyway.

## 5. The custom UUIDs `a6ed0401-…` / `a6ed0201-…`

**Nothing found (searched the full UUIDs, the suffix `d344-460a-8075-b9e8ec90d71b`, and the prefixes on the web and
on grep.app code search — zero BLE-related hits).** None of the three bridge projects mention them; they only use
0x1828 / 0x2A63 / 0x2A55. No link to Telink or any other chipset vendor's known UUID families was found.

Inference (moderate, unsourced): a Nordic-based device with a proprietary app that does "updates and diagnostics"
typically carries a vendor OTA/config service; a6ed0401/a6ed0201 are plausibly that. Their protocol is unknown, so
**the app never writes to them** — it only subscribes to 0402/0202, which is reversible.

## 6. The mismatch in your observation

You reported that 0x2A63 was *not* found under 0x1828 and that only the a6ed characteristics notify. All three
bridges depend on 0x2A63 being inside 0x1828. Possible explanations, none confirmed:

1. Newer firmware ("1.0", model string `csc_sensor_01`) changed the GATT layout.
2. The earlier scanner app truncated or mis-grouped characteristics — the Device tab in this app lists every
   characteristic under every service, so this will be settled on the first run.
3. The meter is in an "unactivated / unbound" state and only exposes its config service until the X-LAB app binds it.

## 7. Does the device need initialization / authentication? — answer

- **Documented by manufacturer:** nothing public.
- **Observed by community:** one unit needed a 4-byte write to 0x2A55; another did not and rejected it.
- **Authentication/pairing:** no evidence either way. The app logs `INSUFFICIENT_AUTHENTICATION (0x05)` /
  `INSUFFICIENT_ENCRYPTION (0x0F)` if the device ever demands bonding; if that appears, pairing the sensor in Android
  Bluetooth settings is the documented, reversible next step.

## 8. Safe next tests (in order)

1. Install **X-LAB Bikes** and check whether it shows power. (Decides sensor-vs-protocol.)
2. Run this app: Scan → confirm XDS-like device → Connect → Device tab: does 0x1828 contain 0x2A63 and 0x2A55?
3. Guided Test (30 s still / 30 s pedaling) with *all* notifications enabled. Export the JSON log.
4. Only if 0x2A55 exists and no data flowed: the opt-in "community start command" button (explicit confirmation
   dialog). Expected outcomes: data starts flowing, or harmless `0x81` rejection.
5. If still nothing: the meter is either asleep/faulty or needs the app's binding handshake. The remaining
   unknown — what X-LAB Connect writes to a6ed0401/0201 — can only be learned by capturing an HCI snoop log
   (Developer options → "Enable Bluetooth HCI snoop log") while the official app connects, then reading it in
   Wireshark. That is a passive capture and requires no root.
