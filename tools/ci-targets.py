#!/usr/bin/env python3
"""Changed paths → the tests that cover them (ios/CI_PROCESS.md).

    python3 tools/ci-targets.py [--since <commit>] [--harness | --quick-ui | --json] [paths...]

Paths come from the arguments, from stdin (one per line), or from `git diff --name-only <since>..HEAD` with --since.
  --quick-ui  (default) prints the QUICK_UI value for ios/ci/build.sh: UI tests, space separated
              (e.g. "LayoutAudit/testHomeStates JourneyTests"). Empty input → the default quick set.
  --harness   prints the Linux-harness suites (TESTS=...) worth running for these paths; "ALL" when unsure.
  --json      prints both plus the reasons.
Mapping is by path, most specific rule first; unknown app files fall back to the default quick set (never to nothing).
"""
import json, re, subprocess, sys

DEFAULT_QUICK = ["LayoutAudit/testKeyScreensAtTextSizes", "LayoutAudit/testHomeStates",
                 "OnboardingScreens/testOnboardingV3FiveStages", "DesignSystemAudit/testGalleryLightAndDark"]
# the hybrid journey on the layout devices (all three personas run, recorded, in the full smoke job)
JOURNEY = "JourneyTests/testHybridJourney"

# (regex on the repo-relative path, UI tests, harness suites, reason)
RULES = [
    (r"ios/BikeComputer/(OnboardingView|OnboardingDraft)\.swift",
     ["OnboardingScreens/testOnboardingV3FiveStages", JOURNEY], ["OnboardingDraftTests"], "onboarding"),
    (r"ios/BikeComputer/(ProfileScreens|ProfileEditors|ProfileView|ProfileSections)\.swift",
     ["LayoutAudit/testKeyScreensAtTextSizes", JOURNEY], ["OnboardingDraftTests", "Rc3EngineTests"], "profile"),
    (r"ios/BikeComputer/(AvailabilityEditor|PlanView|SessionRebuild|SessionChangePreview)\.swift",
     ["LayoutAudit/testRC2OwnerScreens", "LaunchSmokeTests/testUpgradeFromBuild33OpensHybridSheetsAtLargeText"],
     ["Rc3EngineTests", "ModelTests"], "plan / previews"),
    (r"ios/BikeComputer/(HomeView|HomeFirstWeek|HomeModel|HomeSheets)\.swift",
     ["LayoutAudit/testHomeStates", JOURNEY], ["HomeBTests"], "home"),
    (r"ios/BikeComputer/DesignSystem/|ios/BikeComputer/(DesignSystem|Theme)\.swift",
     ["DesignSystemAudit/testGalleryLightAndDark"], ["DesignSystemPureTests"], "design system"),
    (r"ios/BikeComputer/(Ride/|RideView|RideDashboard|RideRecorder)",
     ["RideViewsSmokeTests"], ["ModelTests", "RideControlPlanTests", "RideViewModelTests", "RideRecorderDisconnectTests"], "ride"),
    (r"ios/BikeComputer/(StrengthWorkout|StrengthNextSet|StrengthLog|StrengthCoachViews)\.swift",
     ["LaunchSmokeTests/testUpgradeFromBuild36CentreButtonOpensStrengthWorkout",
      "AdaptiveSmokeTests/testQuickStrengthLogShowsCheckInThenAdjustments", "LayoutAudit/testKeyScreensAtTextSizes"],
     ["StrengthAuditTests", "RoutinesTests"], "strength"),
    (r"ios/BikeComputer/(ConnectionsView|DeviceSettingsView|Connections|DeviceLink|WatchLink|HealthReads|HealthImport)\.swift",
     ["LayoutAudit/testKeyScreensAtTextSizes", JOURNEY], ["S20DataIntegrityTests"], "devices / health"),
    (r"ios/BikeComputer/(Provenance|Models|ProfileSync|WorkoutState)\.swift",
     ["LaunchSmokeTests", JOURNEY], ["ALL"], "data model / migration"),
    (r"ios/BikeComputer/(Rc3Engine|Planning|StrengthPlanner|Strength|Hybrid|AdaptationEngine|Adaptive\w*|CoachSafety|ProgressMetrics|WeekTotals)\.swift",
     ["LayoutAudit/testRC2OwnerScreens", JOURNEY], ["ALL"], "engine"),
    (r"ios/BikeComputer/(ProgressView|TrendCharts)\.swift",
     ["LayoutAudit/testRC2OwnerScreens"], ["ProgressMetricsTests", "Rc3EngineTests"], "progress"),
    (r"ios/BikeComputerUITests/(\w+)\.swift", None, [], "ui test file"),          # the changed test itself
    (r"ios/BikeComputerTests/(\w+)\.swift", [], None, "unit test file"),           # the changed suite itself
    (r"ios/Shared/", ["RideViewsSmokeTests"], ["ALL"], "shared link code"),
    (r"ios/BikeComputerWatch/", [], ["WatchMessageTests"], "watch app (watch job only)"),
    (r"ios/(project\.yml|ci/|.*\.md)|\.github/|tools/", [], [], "build / docs / tooling"),
]

def targets(paths):
    ui, suites, reasons = [], [], []
    unknown_app = False
    for p in paths:
        hit = False
        for rx, u, s, why in RULES:
            m = re.search(rx, p)
            if not m: continue
            hit = True
            if u is None: u = [m.group(1)]                 # a UI test file → run that class
            if s is None: s = [m.group(1)]                 # a unit test file → run that suite
            for t in u:
                if t not in ui: ui.append(t)
            for t in s:
                if t not in suites: suites.append(t)
            reasons.append(f"{p}: {why}")
            break
        if not hit and p.startswith("ios/BikeComputer/"):
            unknown_app = True; reasons.append(f"{p}: no rule → default quick set")
    if unknown_app or (not ui and any(p.startswith("ios/BikeComputer") for p in paths)):
        for t in DEFAULT_QUICK:
            if t not in ui: ui.append(t)
        if "ALL" not in suites: suites.append("ALL")          # an unmapped app file: run every engine suite
    if not paths:
        ui = list(DEFAULT_QUICK); suites = ["ALL"]; reasons.append("no paths → defaults")
    if "ALL" in suites: suites = ["ALL"]
    # a JourneyTests class entry subsumes its methods; keep classes before methods for readability
    return ui, suites, reasons

def main(argv):
    mode = "--quick-ui"; since = None; paths = []
    it = iter(argv)
    for a in it:
        if a in ("--quick-ui", "--harness", "--json"): mode = a
        elif a == "--since": since = next(it)
        else: paths.append(a)
    if since:
        out = subprocess.run(["git", "diff", "--name-only", f"{since}..HEAD"], capture_output=True, text=True)
        paths += [l.strip() for l in out.stdout.splitlines() if l.strip()]
    elif not paths and not sys.stdin.isatty():
        paths += [l.strip() for l in sys.stdin.read().splitlines() if l.strip()]
    ui, suites, reasons = targets(paths)
    if mode == "--json": print(json.dumps({"quick_ui": ui, "harness": suites, "reasons": reasons}, indent=1))
    elif mode == "--harness": print(" ".join(suites))
    else: print(" ".join(ui))

if __name__ == "__main__":
    main(sys.argv[1:])
