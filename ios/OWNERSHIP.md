# Cyclift — data ownership (Checkpoint G, master order 8 Nov §6.1)

One owner per value. Everything else reads. Where two components could write, the rule below says which one does and
how duplicates are prevented. "Phone" = the Cyclift iPhone app; "Watch" = Cyclift on Apple Watch; "Board" = the
BikeComputer; "LILYGO" = the Cyclift Watch (ESP32).

| Value | Owner (writes) | Readers | Rule / duplicate prevention | Code |
|---|---|---|---|---|
| Workout session identity | Phone (`Workout.id`; `RideRecord.id`) | Watch, Board, LILYGO carry the phone's id when they know it | Board rides keyed by `boardId + start` (`importBoardRide`); LILYGO events carry `(deviceId, seq, workoutId)` and are de-duplicated by `DedupFilter` | Models.swift, sync.hpp |
| Recording state (running / paused / ended) | **The recorder of the ride** — Board when the ride started on the Board, else Phone (`RideRecorder.owner`) | Ride screen, Watch mirror | One recorder per ride (`RideControlPlan`); the phone never starts a second recording while the Board records; End on the phone with a lost board link ends the phone's copy only | RideRecorder.swift, Ride/RideControlPlan.swift |
| Workout completion | Phone ledger (`TrainingLedger`: rides, strength logs, manual marks, Health imports) | Home, Plan, Progress | A planned session is matched to at most one record; Health imports already present in Cyclift (`healthUUID` / `healthExportUUID`) are never re-imported | WorkoutState.swift, Ride/RideHealthExport.swift |
| Heart rate (live) | The source device: Watch (`PhoneLink`), BLE strap (`BLESensors`), Board | `SensorHub` chooses ONE reading per metric by source priority and quality | Stale readings (> quality window) are never shown or coached as live; the hub marks `unverified` / `estimated` | Sources/SensorHub.swift |
| Power / cadence (live) | Power meter via Board or direct BLE (`BLESensors`) | SensorHub → Ride, coach | Priority: Board (when recording) → direct BLE → none; never both; invalid / zero samples flagged by the pipeline monitor | Sources/SensorHub.swift, Pipeline/PipelineHealth.swift |
| GPS | Phone (`LocationService`) | Board (fixes sent 1 Hz), Ride map, LILYGO (mirror over BLE) | Only fresh, accurate fixes (`horizontalAccuracy ≥ 0`, age < 2 s) are used; the Board integrates its own distance from the fixes it receives; no component invents a point | LocationService.swift, ride_telemetry.hpp (GpsMirror) |
| Distance | The recorder (Board integrates; Phone `RideRecorder` integrates its own fixes) | Results, Health | Never both: the phone's `distCm` only when it is the recorder | RideRecorder.swift |
| Training plan | Phone (`Store.plan`, planner, versions) | Watch / LILYGO receive today's session read-only | Every change goes edit → preview → apply (`SessionChangePreview`); the watch's logged sets flow back as events, never as plan edits | Planning.swift, SessionRebuild.swift |
| FTP | Phone profile (`RiderProfile.setFTP` — the only writer; value + `FTPHow` + `ValueProvenance{source, recordedAt}` move together) | Coach, zones, Board (profile push), LILYGO (Live frame) | States Unknown / Entered / Estimated / Tested; a suggestion changes nothing until accepted; a **tested** FTP is never replaced by the Board's legacy value or silently by an estimate | Rc3Engine.swift (setFTP), Models.swift (acceptFTPSuggestion), ProfileSync.swift |
| Recovery data (sleep, HRV, resting HR, weight) | Apple Health is the source; Phone `HealthReads` copies the latest samples with source + timestamp | Home recovery card, Recovery page, LILYGO (Cached frame) | One source per night for sleep (APP-031); stale (> 24 h) flagged; absent ≠ zero | HealthReads.swift |
| Apple Health export (workouts) | **Watch** when it recorded the workout (`WorkoutManager`); **Phone** only for phone-only rides, under the approved setting and permission | — | One workout per ride: `RideRecord.healthExportUUID` is set once; the phone never exports a ride the Watch recorded; a denied permission never blocks saving the Cyclift ride | Ride/RideHealthExport.swift, BikeComputerWatch/WorkoutManager.swift |
| Sync status (Board) | Phone (`ProfileSync` record per board) | Devices screen | Phone authoritative after confirmation; the Board's shared settings are overwritten by the phone, never the reverse except by the rider's explicit "adopt" | ProfileSync.swift |
| Sync status (LILYGO) | LILYGO `EventQueue` (unacknowledged events) + Phone `CyWatchSession.acked` (persisted per device) | Connections › Cyclift Watch, watch status screen | Cumulative acks; resend after reconnect; an event with seq ≤ acked is acknowledged again but never re-applied; bounded queue with explicit overflow warning | sync.hpp, Watch/CyWatchLink.swift |
| LILYGO ride controls | Phone `RideRecorder` (or the Board through it) | — | Watch Start/Pause/Resume/Lap/End are commands under the same one-owner rules as the Apple Watch; the LILYGO never creates a ride record | Watch/CyWatchCoordinator.swift |
| LILYGO logged sets | Phone `Store.activeSession` | Strength log | A set event (exercise×100+set, reps, weight×10) marks that set done in the phone's session for the planned workout; Save finishes the session, Discard drops it; an event for an unknown workout with no session open is ignored, never invented | Watch/CyWatchCoordinator.swift |

## Competing recorders — the three cases

1. Board recording, phone connected: the phone mirrors, never records; Lap / Pause / End are sent to the Board.
2. Board recording, link lost: the phone keeps its mirror copy; End on the phone ends the copy and says the Board keeps its own record; on reconnect the Board's ride is imported by `boardId + start` and merged, not duplicated.
3. Phone recording (no Board): the phone is the recorder; the Watch streams heart rate; the Watch writes the Health workout if it ran one, otherwise the phone may (setting + permission).

## What is not yet implemented (tracked)

- Board ride-step / target protocol (R-020): specified separately, firmware change needs the owner's approval; not flashed.
- LILYGO: firmware BLE transport (service `6E400001-…`) and the iPhone companion (`Watch/CyWatchWire.swift`, `CyWatchLink.swift`, `CyWatchCoordinator.swift`) both speak protocol v1; the codecs are cross-checked byte for byte against the firmware's encoder (CyWatchWireTests). The link is Simulator-untestable (CoreBluetooth) and remains **not hardware-tested** until a flashed watch exists; the pure session (reassembly, CRC drop, cumulative ack, duplicate suppression) and event application are unit-tested.
