# S2-0 — Data integrity (owner approval 2 Nov 2026, §1 + §5)

Branch `impl/s2` (from build 127, commit 2860896). Evidence level of everything here: **Linux host tests only** — not compiled
for iOS yet, no simulator run, nothing on real hardware. Release-blocking items GR-20, GR-21, GR-22, GR-45, GR-47, GR-51.

## 1. What changed

| Area | Before (build 127) | After (S2-0) |
|---|---|---|
| Age | `age = 35` default; HR zones computed from it; DOB picker "Done" saved today − 35 years | `age: Int?`, nil by default. Age comes from the date of birth, else the birth year, else an age the athlete typed. No age → `maxHRForZones == nil` → **no heart-rate zones**; rides use effort (RPE) targets; the recovery profile applies no age rule. "Done" on the DOB wheel saves nothing. |
| Weight | `weightKg = 75.0` default, shown as the athlete's weight; sent to the board | `weightKg: Double?`, nil by default. UI shows "Not set"; W/kg only with a real weight; board receives 0. |
| FTP | `ftpW = 225` (weight × W/kg table) with `ftpHow = .assumed`; choosing Entered/Tested before typing saved 200/225 W as "entered" | `ftpW = 0`; the W/kg table is deleted; `setFTP` without watts keeps Unknown; power zones are empty and `zone(forWatts:)` returns 0 while Unknown; `ftpHow` sent to the board as 0 when unknown. |
| Max HR | `estimatedMaxHR` always returned a number (208 − 0.7 × age, age possibly 35) | `maxHRForZones: Int?` — entered value, else Tanaka from a **known** age, else nil; `maxHRIsEstimate`. |
| Provenance | none | `RiderProfile.provenance[field] = ValueProvenance(source, recordedAt, needsConfirmation)` for date of birth, weight, FTP, max HR, resting HR, HRV, sleep. |
| Energy | Apple Health active kcal × 4.184 stored in `RideRecord.kj`, shown "kJ · from power" | `RideRecord.energy: EnergyValue(kind, value)` — `workFromPowerKJ` / `activeKcalAppleHealth` / `legacyUnverified`; the ride screen shows the unit and source of the record; `kj` of a Health import is nil. |
| Device states | colour rules only; "paired" and "connected" and "receiving" collapsed | `DeviceState` (notPaired / paired / connected / receivingData(lastSampleAt) / problem(reason)) + `lastSyncedAt`, derived by `DeviceStateRules` from the real signals; `SensorHub.deviceStates`; the Devices rows print the state word first. |
| Apple Health reads | workouts only | optional, per-kind reads of weight, resting HR, HRV (SDNN) and last night's sleep behind `HealthMetricsProviding`; stored with `.appleHealth` + sample date; precedence rule below; no derived score. |

## 2. Provenance table

| Field | Sources that can set it | Where it is used | When Unknown |
|---|---|---|---|
| Date of birth / age | entered (onboarding, Profile, health check age), legacyUnverified (board, old file) | age → max-HR estimate → HR zones; recovery profile (≥ 60) | no HR zones (effort targets), no age rule |
| Weight | entered, appleHealth, legacyUnverified | W/kg; board profile | "Not set"; W/kg hidden; board gets 0 |
| FTP | entered, estimatedFromRides, measuredTest (verified test ride), legacyUnverified | watt targets, power zones, TSS/IF, board | "Unknown"; no watts/zones/IF; board gets ftp 0 / how 0 |
| Max HR | entered, legacyUnverified (or estimate from age, not stored) | HR zones, live gauge | no HR zones; gauge is a plain 0–220 scale |
| Resting HR | entered, appleHealth, legacyUnverified | board profile (phone zones do not use it — GR-41 unchanged) | "not set" |
| HRV, sleep | appleHealth only | displayed with source and date; **nothing is derived** | "No data" |

`ValueSource.tag` is what the UI prints next to a number: Measured (entered / Apple Health / measured test), Estimated, Unverified, Unknown.

## 3. Migration (schema 3 → 4, `StoreMigration.v4`, idempotent, never deletes a workout, log or ride)

| Old value | Rule | Result |
|---|---|---|
| weight 75.0, no provenance | indistinguishable from "never touched" | **Unknown** (log line); any other weight → kept, `.legacyUnverified`, needs confirmation |
| age 35, no DOB / birth year | the slider default | **Unknown** (log line); age ≠ 35 → kept as unverified (the athlete moved the slider); with a DOB or birth year the slider value is dropped |
| `ftpHow == .assumed` (any watts) | the W/kg assumption | `ftpW = 0`, Unknown (watts kept only in the log line) |
| FTP entered / tested / fromRides, no provenance | provenance cannot be established | kept; `.estimatedFromRides` / `.measuredTest` (verified test) / `.legacyUnverified` + needs confirmation |
| max HR / resting HR present | — | kept, `.legacyUnverified` |
| Health-imported ride with `kj` | written as kcal × 4.184 by build ≤ 127 (exact, unambiguous) | `energy = activeKcalAppleHealth(kj ÷ 4.184)`, `kj = nil` |
| board/phone ride with `kj` and power | — | `energy = workFromPowerKJ(kj)` |
| ride with `kj` but no power | origin unknown | `energy = legacyUnverified(kj)` |

Values adopted from the BikeComputer (`ProfileSync.adoptBoardProfile`) are stored as `.legacyUnverified` with
`needsConfirmation` — the board cannot say where its numbers came from (firmware ≤ 0.7.x invents a starting FTP).

## 4. Unknown propagation

| Value | Phone | Apple Watch | BikeComputer (Link PROFILE_SET) |
|---|---|---|---|
| FTP unknown | "Unknown", RPE/HR targets, no zones | the mirror never carried FTP or watts (verified: no FTP field in the Watch app) | `ftp_w = 0`, `ftp_how = 0`. **Firmware ≤ 0.7.x** then computes `bc_starting_ftp(weight, exp)` for its own coaching (CR-04) — a separate firmware correction is specified; with weight 0 it returns 0, so an athlete with no weight gets no invented FTP on the board either. |
| Weight unknown | "Not set" | n/a | `weight_kg_x10 = 0` ("not set" on the board) |
| Age unknown | no HR zones | n/a | `birth_year = 0` |
| Max HR unknown | no HR zones | n/a (the Watch sends HR, never a zone) | `max_hr = 0` |

## 5. Energy rule

`EnergyValue.kind` decides unit and label: work from power → "kJ · from power"; Apple Health → "kcal · Apple Health
estimate"; legacy → "kJ · unverified (older build)". A Health-imported ride never shows kJ. `RideRecord.energyShown`
derives the record for rides saved before schema 4 by recorder type (never from a Health import).

## 6. Device-state rule (`DeviceStateRules`, pure, `freshWindow = 10 s`)

- BikeComputer: paired keys → **Paired**; BLE link ready → **Connected**; LIVE within 10 s → **Receiving live data**; pairing lost / Bluetooth off (with a paired board) / permission → **Connection problem**; nothing remembered → **Not connected**.
- Apple Watch: not paired → Not connected; app missing → problem; paired + app → Paired; mirror session running → Connected; HR within 10 s → Receiving.
- Direct BLE sensor: set up by the athlete → Paired; link up → Connected; sample within 10 s → Receiving; radio off/unauthorized → problem only when set up.
- Sensors on the board: from the LIVE meter-link code (4 = sending, 2/3/5 = searching, 1 = lost → problem).
- Apple Health: authorized → Connected; a read/import within 60 s → Receiving; wanted but not granted → problem.

Colour: green only while receiving; paired/connected amber; problem red; not set up gray (unchanged Connections rule).

## 7. Apple Health precedence (`HealthPrecedence.decide`)

The newer of the athlete's entry and the Health sample wins. A manual entry made after the sample stays until a newer
sample arrives; an undated manual entry (older file) stays until the athlete changes it; equal dates keep the manual
entry; Unknown or legacy-unverified never beats a dated sample. Only kinds the athlete enabled in Settings are read or
applied (`HealthReadSettings`). The UI shows value · source · date. No readiness score, diagnosis or training conclusion
is derived from weight, resting HR, HRV or sleep.

## 8. Tests (Linux harness `/home/claude/harness-s2`, build-127 sources + S2-0)

`S20DataIntegrityTests.swift`: NoFabricatedDefaultsTests (6), ProvenanceMigrationTests (4: build-121 file, build-127 file,
idempotence/round-trip, moved slider), EnergyUnitTests (2), DeviceStateTests (5), HealthPrecedenceTests (5).
Updated expectations: `ModelTests.testPowerZonesOnlyFromAKnownFTP` (was …AndFTPAssumption), `RulesTests.testSkippedOnboardingValuesStayUnknown`,
`Rc3EngineTests.testMigrationV3KeepsEverythingAndMapsFields` (schema 4, FTP 0), `Rc3EngineTests.testAT_E3_1` (HR zones need a max HR),
`AdaptationEngineTests.testMissingSensors…` (HR-only load needs HR zones), `HybridTests` (activeKcal).

Result: **266 tests, 4 failures — all in `HomeBTests.testFirstMultiMissedAndFree`, which also fails on the untouched
build-127 code today (it places sessions at −1/−3 days and today is a Monday, so they fall in last week). Not S2-0.**
CI simulator: pending. Real device: none.

## 9. Not done / open

- The Watch and board firmware are unchanged (no flash). CR-04 (board invents FTP when weight > 0) stays until the firmware correction is approved.
- Resting HR is still unused by the phone's zone model (GR-41, needs an engine-rule approval).
- `DesignSystem.swift` had one line edited (the FTP "starting assumption" sentence) — the design-system fork owns that file; merge carefully.
