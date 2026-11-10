# Cyclift Watch — Bluetooth architecture (Milestone D, document only) — 11 Nov 2026

Status: **design document; no code, no radio, no protocol change.** The wire format stays `BLE_PROTOCOL.md` v1
(unchanged). Bluetooth work is Stage 2b/4 and needs the owner's approval; the iPhone application is not modified here.

## 1. Roles and ownership (unchanged project rules)

| Data | Owner | Watch role |
|---|---|---|
| Training plan, workouts, coach, Apple Health records | iPhone | shows them; never edits the plan |
| Time of day and time zone | iPhone (TimeSync 0x02) | keeps time on the clock chip between syncs |
| Watch-side events (start, pause, lap, set logged…) | watch until acknowledged | queues, resends after reconnect, never duplicates |
| Live sensor values (power, HR, cadence) | whichever device records the ride (one recorder per ride) | displays with age; greys stale values |

## 2. Where RC1 already prepares for it (computer-tested)

| Interface in RC1 | Future Bluetooth message | Note |
|---|---|---|
| `Model::setClock(Clock)` + `Clock.valid` | TimeSync 0x02 | invalid clock hides time and date; the serial `T` command is a temporary stand-in |
| `Model::synced` / `setDemo()` | Hello 0x01 + PlanToday 0x10 | "not synced" is the default; demo data stands in for PlanToday |
| `Model::phoneLinked`, pending command states, `Reply::Refuse / NoAnswer` | Event 0x30 / Ack 0x31 / Error 0x7F | the simulated iPhone already produces sent → confirmed / refused / no answer |
| `Model::setMetrics(power, hr, cadence)`, `Sensors` | Live 0x20 | missing sensor = "—", never 0 |
| Coach widget text | Coach 0x22 | one primary message |

The UI never talks to Bluetooth directly: a future `link` module turns frames into these model calls, so the screens
need no change when Bluetooth arrives (project rule: iPhone UI changes do not require firmware changes).

## 3. Staleness, reconnection, versions

From protocol v1 (already approved text):
- Live and Gps carry the measurement age; the watch greys stale values and never interpolates recorded data.
- Reconnection: the watch resends everything unacknowledged; the iPhone processes each `(deviceId, seq)` once.
- A frame with another `ver` is refused whole (never half-read).

Proposals (not in v1; need approval before Stage 4):
- Staleness thresholds (when a value turns grey, when it becomes "—").
- Hello reports firmware and protocol versions so the iPhone can show a readable "update the watch" message.
- One bonded iPhone per watch; unpairing removes the bond but keeps unacknowledged events.

## 4. Memory budget (measured facts, Stage 1.1/1.2)

- The Bluetooth controller reserves **56,156 B** of internal RAM; the earlier v2 BLE build used **128,424 of 131,072 B**
  IRAM. Therefore the IRAM rendering speed-up stays **off** in every Bluetooth build (Stage 1.2 decision).
- Stage 1.1 measured **121,028 B** free (min 94,500 B) with the IRAM speed-up on; Stage 1.2/RC1 predicted ~124 KB usable
  8-bit heap (prediction, to be measured with `M` in the acceptance session).
- Rule for Stage 4: Bluetooth may start only if `M` shows ≥ 80 KB 8-bit internal heap after it is up, with a
  10-minute soak at the 1 Hz cockpit rate. The LVGL pool (64 KB, peak sampled ≤ 15.2 KB on the computer) is the first
  candidate to shrink, only with on-watch `M` evidence.

## 5. Open decisions for the owner (not taken here)
1. The proposals in section 3. 2. Whether the watch or the BikeComputer records rides when both are present (current
rule: the board records when connected). 3. When notifications (ANCS) enter scope.
