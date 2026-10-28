#!/usr/bin/env bash
# Linux engine unit tests: engine sources + the pure engine test files. Usage: test.sh <checkout> [filter]
set -euo pipefail
SRC="$1"; FILTER="${2:-}"; HERE="$(cd "$(dirname "$0")" && pwd)"; W="$HERE/testws"
rm -rf "$W/Sources" "$W/Tests"; mkdir -p "$W/Sources/BikeComputer" "$W/Tests/BikeComputerTests"
for f in Models Strength WorkoutState Hybrid Planning StrengthPlanner AdaptationEngine AdaptiveModels AdaptiveStore UITestSupport CoachSafety; do
  sed -e 's/^import Combine$//' -e 's/@retroactive //' "$SRC/ios/BikeComputer/$f.swift" > "$W/Sources/BikeComputer/$f.swift"
done
# Home / weekly totals / Progress maths (pure Foundation; present from the RC2 UX work on)
for f in WeekTotals ProgressMetrics HomeModel; do
  [ -f "$SRC/ios/BikeComputer/$f.swift" ] && sed -e 's/^import Combine$//' -e 's/@retroactive //' "$SRC/ios/BikeComputer/$f.swift" > "$W/Sources/BikeComputer/$f.swift"
done
cp "$SRC/ios/Shared/BCLink.swift" "$SRC/ios/Shared/AppInfo.swift" "$SRC/ios/Shared/CoachCore.swift" "$W/Sources/BikeComputer/"
cp "$HERE/Sources/BikeComputer-shims/"*.swift "$W/Sources/BikeComputer/"
for t in ${TESTS:-TestScreenSupport IndependentReviewPass2ProbeTests IndependentReviewPass2Probe2Tests IndependentReviewPass2Probe3Tests IndependentReviewPass3ProbeTests IndependentReviewPass3Probe2Tests IndependentReviewPass4ProbeTests CoachRemediationPass3Tests IndependentReviewProbeTests IndependentReviewProbe2Tests IndependentReviewProbe3Tests AdaptationEngineTests HybridV2Tests HybridTests RoutinesTests StrengthAuditTests AuditFixTests QualityReleaseTests CoachRemediationTests HomeBTests ProgressMetricsTests}; do
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
swift build --build-tests > build.log 2>&1; B=$?
grep -E "error:|Build complete" build.log | tail -40
[ $B -eq 0 ] || exit $B
mkdir -p .build/debug && cp "$SRC/ios/BikeComputer/Resources/exercises.json" .build/debug/
if [ -n "$FILTER" ]; then swift test --skip-build --filter "$FILTER" > test.log 2>&1; R=$?; tail -60 test.log
else swift test --skip-build > test.log 2>&1; R=$?; grep -E "error|failed|Executed|passed at" test.log | tail -60; fi
exit $R
