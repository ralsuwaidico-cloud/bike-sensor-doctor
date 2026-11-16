#!/usr/bin/env bash
# Linux engine unit tests: engine sources + the pure engine test files. Usage: test.sh <checkout> [filter]
set -euo pipefail
SRC="$1"; FILTER="${2:-}"; HERE="$(cd "$(dirname "$0")" && pwd)"; W="$HERE/testws"
rm -rf "$W/Sources" "$W/Tests"; mkdir -p "$W/Sources/BikeComputer" "$W/Tests/BikeComputerTests"
for f in Models StoreRecovery Strength WorkoutState Hybrid Planning StrengthPlanner AdaptationEngine AdaptiveModels AdaptiveStore UITestSupport CoachSafety; do
  [ -f "$SRC/ios/BikeComputer/$f.swift" ] || continue      # E1: an older checkout (the build-216 fixture run) has no StoreRecovery
  sed -e 's/^import Combine$//' -e 's/@retroactive //' "$SRC/ios/BikeComputer/$f.swift" > "$W/Sources/BikeComputer/$f.swift"
done
# Home / weekly totals / Progress maths (pure Foundation; present from the RC2 UX work on)
for f in WeekTotals ProgressMetrics HomeModel SessionRebuild Rc3Engine Provenance HealthReads RecoveryModel OnboardingDraft NextSet HomeDashboardModel HomeSummaries ProfileMenuModel; do
  [ -f "$SRC/ios/BikeComputer/$f.swift" ] && sed -e 's/^import Combine$//' -e 's/@retroactive //' "$SRC/ios/BikeComputer/$f.swift" > "$W/Sources/BikeComputer/$f.swift"
done
cp "$SRC/ios/Shared/BCLink.swift" "$SRC/ios/Shared/AppInfo.swift" "$SRC/ios/Shared/CoachCore.swift" "$W/Sources/BikeComputer/"
cp "$HERE/Sources/BikeComputer-shims/"*.swift "$W/Sources/BikeComputer/"
[ -f "$SRC/ios/BikeComputer/DesignSystem/ThemeTokens.swift" ] && cp "$SRC/ios/BikeComputer/DesignSystem/ThemeTokens.swift" "$W/Sources/BikeComputer/"   # UX1 theme foundation (Foundation only)
[ -f "$SRC/ios/BikeComputer/DesignSystem/PureDesign.swift" ] && cp "$SRC/ios/BikeComputer/DesignSystem/PureDesign.swift" "$W/Sources/BikeComputer/"   # design-system pure logic (Foundation only)
# Checkpoints C2 / D / F / E pure models (Foundation only)
for f in ProgressAnalytics PlanSummaries Ride/RideViewModels Ride/RideStepsSync; do
  [ -f "$SRC/ios/BikeComputer/$f.swift" ] && sed -e 's/^import Combine$//' "$SRC/ios/BikeComputer/$f.swift" > "$W/Sources/BikeComputer/$(basename $f).swift"
done
for t in ${TESTS:-E1DataIntegrityTests E1SafetyContractsTests ThemeTokensTests TestScreenSupport IndependentReviewPass2ProbeTests IndependentReviewPass2Probe2Tests IndependentReviewPass2Probe3Tests IndependentReviewPass3ProbeTests IndependentReviewPass3Probe2Tests IndependentReviewPass4ProbeTests CoachRemediationPass3Tests IndependentReviewProbeTests IndependentReviewProbe2Tests IndependentReviewProbe3Tests AdaptationEngineTests HybridV2Tests HybridTests RoutinesTests StrengthAuditTests AuditFixTests QualityReleaseTests CoachRemediationTests HomeBTests ProgressMetricsTests Rc3EngineTests S20DataIntegrityTests DesignSystemPureTests EngineSideEffectTests OnboardingDraftTests W12AndDockTests SupersetPipelineTests HomeDashboardTests HomeSummariesTests ProfileMenuTests RecoveryAnalysisTests ProgressAnalyticsTests FTPOwnershipTests DataIntegrityGapTests RideChainTests RideStepsSyncTests RideViewModelTests PlanSummariesTests}; do
  [ -f "$SRC/ios/BikeComputerTests/$t.swift" ] && cp "$SRC/ios/BikeComputerTests/$t.swift" "$W/Tests/BikeComputerTests/" && python3 "$HERE/strip_ui_tests.py" "$W/Tests/BikeComputerTests/$t.swift"
done
if [ -n "${EXTRA:-}" ]; then cp $EXTRA "$W/Tests/BikeComputerTests/"; fi
cat > "$W/Package.swift" <<'P'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "CycliftEngineTests", targets: [
  .target(name: "BikeComputer", path: "Sources/BikeComputer"),
  .testTarget(name: "BikeComputerTests", dependencies: ["BikeComputer"], path: "Tests/BikeComputerTests"),
])
P
cd "$W"
# exit status: non-zero when the build or any test fails (CI uses it; the filtered output stays the same for people)
B=0; swift build --build-tests > build.log 2>&1 || B=$?   # E1: with `set -e` a failing command ended the script before its result was printed
grep -E "error:|Build complete" build.log | tail -40 || true
[ $B -eq 0 ] || exit $B
mkdir -p .build/debug && cp "$SRC/ios/BikeComputer/Resources/exercises.json" .build/debug/
R=0
if [ -n "$FILTER" ]; then swift test --skip-build --filter "$FILTER" > test.log 2>&1 || R=$?; tail -60 test.log
else swift test --skip-build > test.log 2>&1 || R=$?; grep -E "error|failed|skipped|Executed|passed at|became|missing after save|type changed|^E1-" test.log | tail -400 || true
  # E1: a test run that ends without a summary (a crash) used to print nothing at all; show where it stopped
  grep -q "Executed [0-9]* tests" test.log || { echo "== no test summary (exit $R) — last 40 lines of test.log:"; tail -40 test.log; [ $R -ne 0 ] || R=1; }
fi
exit $R
