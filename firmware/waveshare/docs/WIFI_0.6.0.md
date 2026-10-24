# Wi-Fi in firmware 0.6.0 — what was wrong, what changed, what only the hardware can confirm

Rashed's report on 0.5.0: "Wi-Fi only gives ON/OFF" (Quick Settings) and "my iPhone hotspot is not found / not connected".
The Wi-Fi manager (`main/net_wifi.c`) and the Wi-Fi screens (`main/ui/ui_wifi.c`) existed since 0.3.0; 0.6.0 reworks both and
adds setup from the phone over the secure Bluetooth link.

## Findings (code review, not yet confirmed on the device)

| # | Suspect | Finding | Change in 0.6.0 |
|---|---|---|---|
| 1 | Quick Settings tile | The tile only toggled the radio; the full page was two levels deep in Settings | Tap = full Wi-Fi page, hold = on/off; the page has the switch too |
| 2 | iPhone hotspot radio band | iPhone 12 and later run the hotspot on **5 GHz** unless *Settings → Personal Hotspot → Maximize Compatibility* is ON; the ESP32-S3 has no 5 GHz radio, so the network is simply invisible. The hotspot also only broadcasts while the Personal Hotspot screen is open or a client is already connected | Explained in the empty state, under the list, and in the NOT FOUND result; the phone app gets the same text |
| 3 | Scan dwell | 40–100 ms per channel: an AP beaconing every ~100 ms can be missed on a single pass | 120–300 ms per channel, channels 1–13 (country AE), 32 records instead of 20, 32 entries kept |
| 4 | Network name | iOS names the hotspot "Rashed’s iPhone" with a **typographic apostrophe U+2019**. Store, compare and connect already used raw UTF-8 bytes (correct). The LVGL fonts have no U+2019 glyph: the name rendered with a missing-glyph box, and a name typed on the ring keyboard ("Rashed's iPhone", ASCII) can never match | Display sanitiser: ’ ‘ “ ” – — shown as ' ' " " - -; matching keeps the real bytes. Phone-side setup carries the exact bytes. "Other network" (typed names) stays for hidden networks only |
| 5 | Authentication | iOS hotspots announce WPA2/WPA3-Personal transition with PMF. The config used threshold WPA_PSK, PMF capable, SAE both — plausible, but WPA2 threshold is the documented setting for transition APs | `threshold.authmode = WPA2_PSK`, `pmf_cfg.capable = true, required = false`, `sae_pwe_h2e = BOTH` |
| 6 | Reconnection | Scan + connect every 5/10/30/60 s for ever while a saved network is out of range (radio time, battery) | Backoff 5 → 60 s, **stops after 10 failed rounds** until the rider rescans, opens the Networks page, connects or saves a network; no periodic scanning otherwise |
| 7 | "Connected" without data | A hotspot can hand out an address with no internet (phone without data, captive page) and the board said CONNECTED | One DNS lookup (`captive.apple.com`) after the address: "internet ok" / "no internet" / "connected, internet not checked" |
| 8 | Scan while connecting | A scan requested while a connect attempt ran was dropped silently (device `do_scan` returns during CONNECTING) | The phone-service scan is deferred until the attempt ends (≤ 25 s) and reported honestly if it still fails |
| 9 | Coexistence | One shared 2.4 GHz radio for Wi-Fi and Bluetooth; modem power save stays on; the manager never scans during a ride | Unchanged; a **manual** scan during a ride is allowed from the Networks page with a warning; the phone's scan request during a ride is answered BUSY |
| 10 | Credentials in logs | None found (SSIDs are not logged either; passwords are wiped after use) | Kept; the phone path copies the password straight into the manager and wipes it |

Most likely cause of "not discovered": #2 (5 GHz hotspot / hotspot screen closed) and #4 (ASCII apostrophe typed by hand).
Most likely cause of "not connected" after discovery: #5 (if the AP insisted on PMF/WPA3 behaviour) or a password typo on the ring keyboard.

## What the rider does (checklist, also in pc-kit/TEST-v0.6.0.txt)
1. iPhone: Settings → Personal Hotspot → **Maximize Compatibility ON**, leave that screen open.
2. Board: Quick Settings → tap Wi-Fi → Networks → the hotspot appears as `Rashed's iPhone` with signal bars.
3. Easiest: BikeComputer app → Profile → Devices → BikeComputer → Wi-Fi → pick the hotspot → password on the phone keyboard.
   On-device: tap the network → ring keyboard → JOIN.
4. Expect CONNECTING → CONNECTED + "internet ok" (or "no internet" when the phone has no data). WRONG PASSWORD / NOT FOUND are shown as such.

## Simulator coverage (test/sim scenarios 11 and 15)
Scan listing with signal bars / open / saved tags, UTF-8 name shown with a plain apostrophe, detail page (connect, new password, hold to forget,
back), ring keyboard, wrong password, timeout, not found, no address, connected + internet / no-internet, rescan, saved networks, forget,
auto-reconnect after a restart, network loss → fallback to the other saved network, no automatic activity during a ride, Wi-Fi toggled during a
ride keeps the ride, and the whole BLE provisioning flow (status, scan, set wrong/right, forget, busy during a ride, radio off).

## Only the hardware can confirm
- That the hotspot is actually seen with the longer dwell (depends on the iPhone model and "Maximize Compatibility").
- That WPA2/WPA3-transition association succeeds with the new threshold/PMF settings.
- Scan duration (~2–4 s expected) and whether the XDS link shows a gap during a manual scan in a ride.
- The DNS check timing on a real hotspot (a few seconds at most; it only delays the "internet ok" text).
