#!/usr/bin/env bash
# Linux engine unit tests: engine sources + the pure engine test files. Usage: test.sh <checkout> [filter]
set -euo pipefail
SRC="$1"; FILTER="${2:-}"; HERE="$(cd "$(dirname "$0")" && pwd)"; W="$HERE/testws"
rm -rf "$W/Sources" "$W/Tests"; mkdir -p "$W/Sources/BikeComputer" "$W/Tests/BikeComputerTests"
for f in Models Strength WorkoutState Hybrid Planning StrengthPlanner AdaptationEngine AdaptiveModels AdaptiveStore UITestSupport CoachSafety; do
  sed -e 's/^import Combine$//' -e 's/@retroactive //' "$SRC/ios/BikeComputer/$f.swift" > "$W/Sources/BikeComputer/$f.swift"
done
cp "$SRC/ios/Shared/BCLink.swift" "$SRC/ios/Shared/AppInfo.swift" "$SRC/ios/Shared/CoachCore.swift" "$W/Sources/BikeComputer/"
cp "$HERE/Sources/BikeComputer-shims/"*.swift "$W/Sources/BikeComputer/"
for t in ${TESTS:-TestScreenSupport IndependentReviewPass2ProbeTests IndependentReviewPass2Probe2Tests IndependentReviewPass2Probe3Tests IndependentReviewPass3ProbeTests IndependentReviewPass3Probe2Tests CoachRemediationPass3Tests IndependentReviewProbeTests IndependentReviewProbe2Tests IndependentReviewProbe3Tests AdaptationEngineTests HybridV2Tests HybridTests RoutinesTests StrengthAuditTests AuditFixTests QualityReleaseTests CoachRemediationTests}; do
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
cd "$W" && swift build --build-tests 2>&1 | grep -E "error:|Build complete" | tail -40
mkdir -p .build/debug && cp "$SRC/ios/BikeComputer/Resources/exercises.json" .build/debug/
if [ -n "$FILTER" ]; then swift test --skip-build --filter "$FILTER" 2>&1 | tail -60; else swift test --skip-build 2>&1 | grep -E "error|failed|Executed|passed at" | tail -60; fi
