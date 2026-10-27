#!/usr/bin/env bash
# Rebuilds and runs the Cyclift coach audit harness (audited commit 2b2c104).
# Usage: run.sh <path to a checkout of 2b2c104> <output dir>
# Needs a Linux Swift 5.10+ toolchain (here: Ubuntu swiftlang 5.10.1-2 extracted to /opt/swiftx).
set -euo pipefail
SRC="$1"; OUT="$2"; HERE="$(cd "$(dirname "$0")" && pwd)"; W="$(mktemp -d)"
mkdir -p "$W/Sources/BikeComputer" "$W/Sources/Harness" "$W/Tests/BikeComputerTests"
for f in Models Strength WorkoutState Hybrid Planning StrengthPlanner AdaptationEngine AdaptiveModels AdaptiveStore UITestSupport CoachSafety; do
  sed -e 's/^import Combine$//' -e 's/@retroactive //' "$SRC/ios/BikeComputer/$f.swift" > "$W/Sources/BikeComputer/$f.swift"
done
cp "$SRC/ios/Shared/BCLink.swift" "$SRC/ios/Shared/AppInfo.swift" "$SRC/ios/Shared/CoachCore.swift" "$W/Sources/BikeComputer/"
cp "$HERE/Sources/BikeComputer-shims/"*.swift "$W/Sources/BikeComputer/"
cp "$HERE/Sources/Harness/"*.swift "$W/Sources/Harness/"
cp "$HERE/Package.swift" "$W/"
# optional: the repo's own engine tests
for t in AdaptationEngineTests HybridV2Tests RoutinesTests StrengthAuditTests; do cp "$SRC/ios/BikeComputerTests/$t.swift" "$W/Tests/BikeComputerTests/"; done
cd "$W" && swift build -Xswiftc -enable-testing
cp "$SRC/ios/BikeComputer/Resources/exercises.json" .build/debug/
.build/debug/Harness "$OUT"
python3 "$HERE/tools/make_csv.py" "$OUT" "$OUT"
