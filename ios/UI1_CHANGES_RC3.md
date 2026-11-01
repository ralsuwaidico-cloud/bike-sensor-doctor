# rc3 UI part 1: Profile, Devices & Connections, Settings, health check entry points, Home week strip

Owner brief, 1 Nov 2026 15:29. Branch `ui/profile-nav`. Local only, not compiled: SwiftUI can't be built on Linux, so the iOS CI run is the first compile.

## Removed
- **Old Profile category menu**, plus the pages "Rider information", "Training profile" and "App & device settings".
  - They overlapped, so their rows were moved to the single Profile screen. No setting was deleted.
- **Gender and Height rows.** No feature reads them.
  - Height is also out of onboarding r7.
  - The stored values stay in the profile and are still exported.
- **"Training history" block** on the old Training profile page. It duplicated Progress / Plan history.
- **"Firmware needed 0.6.0" and "Protocol" rows.** These were technical information.
  - Firmware and protocol are still on the BikeComputer page (Status).
- **Internet row in Connections.** The app works offline, so it was information only.
  - Bluetooth now shows only when it is not ready.
- **Home's weekly totals card** (`HomeWeekCard` / `HomeWeekBar`).
  - The full weekly numbers live in Progress (owner decision 1 Nov: no duplication).
- **Health check "answer the questions" line on Home**, and the Profile › Health check row.
  - The unused `HealthCheckHomeCard` was deleted.

## Merged
- **"Connections & devices" page:** now the inline section Profile › Devices & Connections, built from one component, `DevicesConnectionsRows`.
  - Rows: Apple Watch, BikeComputer, power meter and strap via the board, Bluetooth sensors paired with this phone plus "Add", Apple Health, Phone GPS, Diagnostics.
  - Each row opens its existing detail page, which holds connect, disconnect, forget and repair. BLE flows are unchanged.
  - `ConnectionsView` (still opened from Ride › Manage) shows the same rows plus "In use now" and the pipeline banner. It is not a second settings page.
- **"App & device settings":**
  - Units, Appearance, Notifications and the Privacy policy moved to Profile › Settings (inline).
  - Screen-on, phone-only recording, ride tiles and coach settings moved to Settings › Ride & coach.
  - Board auto-connect, sync status, firmware, device settings and Wi-Fi moved to the BikeComputer page. The sync status row is now always a link.
- **Strength items** (routines, routine per weekday, my exercises, programming), plus recovery, coach adjustments, hybrid plan and other sports: moved to Profile › Training › Preferences.

## Simplified
- **One Profile screen** with Personal, Training, Devices & Connections, Settings, then Your data and About.
- **Training section** uses short segmented controls:
  - Type: Cycling / Strength / Hybrid.
  - Priority.
  - Level: Beginner / Intermediate / Advanced.
  - Goal (a list page without hints).
  - Week: 7 day icons (bicycle / dumbbell / moon); tapping opens the existing availability editor.
  - Time (sessions and hours a week).
  - Equipment.
  - FTP.
  - Heart rate.
  - Preferences.
- **Weight:** a compact stepper in place of a slider.
- **Home "Week":** seven day cells (bicycle = ride, dumbbell = strength, crescent moon = rest / recovery).
  - Today is highlighted and a check marks a finished day.
  - Tapping a day opens that day's session (`WorkoutDetail`); a day without a session opens Plan.
- **Health check form intro** is now one line: "Optional yes/no questions…".

## Fixed
- **Each setting has one home.** Before, phone-only mode, auto-connect, sync status and the privacy policy each appeared on two pages.
- **Health check (APP-012, owner decision 1 Nov):** no questionnaire in onboarding or ordinary navigation. These protections remain:
  - **Pause training** (Profile › Settings › Health & safety). It uses the existing illness pause (`HealthScreen.currentIllness` → status paused → no sessions). Turning it on or off rebuilds the plan and the ride safety.
  - **Saved answers from earlier versions** still apply (Home hold card, "clearance needed" line, paused centre button). They can be reviewed from Health & safety › Review, which opens the unchanged `HealthCheckView`.
  - **A stop-and-seek-advice notice** on the Health & safety page.
  - **Engine safeguards are not touched by this UI work:** pain reports, load limits and missing-sensor handling.

## UI tests updated
- **LaunchSmokeTests:** Profile › Goal replaces "Training profile". Export and Delete are reached with up to 10 swipes, because the section now comes after Settings.
- **LayoutAudit:**
  - Profile lower-part screenshots replace the training-profile screenshots.
  - The Devices rows are inline in Profile, located by the `deviceBoard` identifier.
  - Home state "pending" must not show the health line; "clearance" still must.
- **OnboardingScreens:** after Start, it asserts that no health-check line appears on Home. The old health-check screenshot step was removed.

## TODO(rc3-engine) hooks left in the code
1. **Date of birth:** `ProfileView` › Personal shows "Birth year" until the profile stores date of birth (onboarding r7).
2. **Separate strength experience:** Hybrid shows "Strength level: Same as cycling" (GR-04/05). For Strength-only, the single `level` is labelled "Strength level".
3. **Session length** (minutes per session, GR-03): `WeeklyTimePage` shows rides/lifts and hours a week only.
4. **FTP source** (Unknown / Entered / Estimated / Tested): the FTP row still shows watts and the existing label. An unknown FTP must show "Unknown".
5. **Plan-affecting profile changes** should go through propose → preview → apply (GR-07/08). Today they save directly, as before; the mode change still regenerates weeks without a saved availability.
6. **HomeModel still emits `HomeCaution.pending`** for "not answered". `HomeView` filters it out; drop it in HomeModel.
7. **Dedicated pause flag:** a pause set on a profile without health answers creates a `HealthScreen` whose other answers read "no". With "not answered" no longer limiting training, that has the same effect, but a dedicated flag is cleaner.

## For the merge
- `HomeSheets.swift` (engine fork's file) still links `HealthCheckView` from the hold sheet. That is correct for existing restrictions; keep it.
- `OnboardingView.swift` was not changed. It never contained the health check (Home asked for it after Start). The r7 rebuild comes later.
