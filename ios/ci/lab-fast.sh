#!/bin/bash
# Cyclift Lab — FAST focused check. Builds the Lab app and its screen checks ONCE (build-for-testing), then runs only
# the selected checks from that same build (test-without-building) and keeps their screenshots. No production build, no
# six-theme sweep, no signing, no upload. It does NOT replace the full Lab run (ios/ci/lab.sh), which stays the gate for
# integration and release candidates. Usage: lab-fast.sh "LabFast/testScreens LabChecks/test2e…"
set -uo pipefail
cd "$(dirname "$0")/.."
TESTS="${1:-LabFast/testScreens}"
case " $TESTS " in *" clean "*) LAB_FAST_CLEAN=1; TESTS=$(echo " $TESTS " | sed "s/ clean / /");; esac
OUT="$PWD/build/lab-out"; rm -rf "$OUT"; mkdir -p "$OUT"
R="$OUT/REPORT.txt"; say() { echo "$*" | tee -a "$R"; }
say "FAST focused Lab check — selected: $TESTS"
T0=$SECONDS
command -v xcodegen >/dev/null || brew install xcodegen >/dev/null 2>&1
xcodegen generate --spec project-lab.yml > "$OUT/xcodegen.txt" 2>&1 || { say "RESULT generate: FAILED"; tail -20 "$OUT/xcodegen.txt"; exit 1; }
SIM=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]; best=None
for rt,devs in d.items():
    if ".iOS-" not in rt: continue
    ver=tuple(int(x) for x in rt.split(".iOS-")[1].split("-"))
    for x in devs:
        if x["name"].startswith("iPhone") and "SE" not in x["name"] and (best is None or ver>best[0]): best=(ver,x["udid"],x["name"])
print(best[1] if best else "")')
[ -n "$SIM" ] || { say "RESULT: no simulator"; exit 1; }
xcrun simctl boot "$SIM" >/dev/null 2>&1 &      # the simulator starts while the app compiles
# ---- build kept from an earlier fast run (restored by the workflow), so only changed files are compiled again ----
# Safe use: every tracked source file gets one fixed date, and only the files that differ from the commit the kept
# build was made from get today's date — so the compiler rebuilds exactly those. If that commit is unknown or cannot
# be compared, or the request says "clean", the kept build is thrown away and everything is built from nothing.
DD=build/lab-dd; MODE=clean; CHANGED=0
git ls-files -z . | xargs -0 touch -t 202001010000 2>/dev/null
defaults write com.apple.dt.XCBuild IgnoreFileSystemDeviceInodeChanges -bool YES 2>/dev/null
OLD=$(cat "$DD/.built-sha" 2>/dev/null || true)
if [ "${LAB_FAST_CLEAN:-0}" = "1" ] || [ -z "$OLD" ] || ! git cat-file -e "$OLD^{commit}" 2>/dev/null; then
  rm -rf "$DD"
else
  MODE="kept build from ${OLD:0:8}"
  CHANGED=$(git diff --name-only "$OLD" HEAD -- . | wc -l | tr -d ' ')
  git diff --name-only -z --diff-filter=d "$OLD" HEAD -- . | (cd "$(git rev-parse --show-toplevel)" && xargs -0 touch 2>/dev/null)
  if ! git diff --quiet "$OLD" HEAD -- project-lab.yml project.yml; then rm -rf "$DD"; MODE="clean (project definition changed)"; fi
fi
STAMP="$OUT/.start"; touch "$STAMP"
say "BUILD MODE: $MODE · files changed since then: $CHANGED"
say "TIME setup: $((SECONDS-T0))s"
T=$SECONDS
xcodebuild build-for-testing -project CycliftLab.xcodeproj -scheme CycliftLab -configuration Debug -destination "id=$SIM" \
  -derivedDataPath "$DD" -clonedSourcePackagesDirPath build/spm CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO > "$OUT/build.log" 2>&1
BS=$?
if [ $BS -ne 0 ] && [ "$MODE" != "clean" ]; then      # a kept build must never be the reason for a failure: once more from nothing
  say "  note: the build on the kept files failed — building again from nothing"; rm -rf "$DD"; MODE="clean (after a failed kept build)"
  xcodebuild build-for-testing -project CycliftLab.xcodeproj -scheme CycliftLab -configuration Debug -destination "id=$SIM" \
    -derivedDataPath "$DD" -clonedSourcePackagesDirPath build/spm CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO > "$OUT/build.log" 2>&1
  BS=$?
fi
say "  compiled in this run: $(grep -cE "^(SwiftCompile|CompileSwift) " "$OUT/build.log") Swift compile step(s)"
if [ $BS -eq 0 ] && [ "$CHANGED" != "0" ] && [ -z "$(find "$DD/Build/Products/Debug-iphonesimulator" -type f -newer "$STAMP" 2>/dev/null | head -1)" ]; then
  say "  FAIL source changed but nothing was rebuilt — refusing to test an old app"; exit 1
fi
[ $BS -eq 0 ] && git rev-parse HEAD > "$DD/.built-sha" && rm -rf "$DD/Logs" "$DD/Index.noindex" 2>/dev/null
(exit $BS)
if [ $? -ne 0 ]; then say "RESULT build: FAILED · $((SECONDS-T))s"; grep -E " error: " "$OUT/build.log" | sed -E 's#.*/ios/##' | sort -u | head -40 | tee -a "$R"; tail -c 200000 "$OUT/build.log" > "$OUT/build-tail.log"; rm "$OUT/build.log"; exit 1; fi
say "RESULT build (app + screen checks, once): ok"; say "TIME build: $((SECONDS-T))s"; rm "$OUT/build.log"
# the same isolation facts the full run reads from the built app (identity and no production keys)
APP=$DD/Build/Products/Debug-iphonesimulator/CycliftLab.app
BIDV=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist" 2>/dev/null)
[ "$BIDV" = "com.ralsuwaidico.cycliftlab" ] && say "  ok   app identity is the Lab's own" || { say "  FAIL app identity: $BIDV"; exit 1; }
for k in SUPABASE_URL SUPABASE_ANON_KEY NSBluetoothAlwaysUsageDescription NSLocationWhenInUseUsageDescription UIBackgroundModes; do
  /usr/libexec/PlistBuddy -c "Print :$k" "$APP/Info.plist" >/dev/null 2>&1 && { say "  FAIL present in the Lab app: $k"; exit 1; }
done
say "  ok   no production keys, Bluetooth, location or background modes in the built app"
T=$SECONDS; xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1; say "TIME waiting for the simulator after the build: $((SECONDS-T))s"
ONLY=(); for t in $TESTS; do ONLY+=("-only-testing:CycliftLabUITests/$t"); done
T=$SECONDS
TEST_RUNNER_LAYOUT_DIR="$OUT" xcodebuild test-without-building -project CycliftLab.xcodeproj -scheme CycliftLab -configuration Debug -destination "id=$SIM" \
  -derivedDataPath "$DD" "${ONLY[@]}" > "$OUT/uitest.log" 2>&1
UT=$?
grep -E "Test Case .*(passed|failed)|error: |Executed [0-9]+ tests" "$OUT/uitest.log" | sed -E 's#.*/ios/##' | sort -u | cut -c1-400 | tee -a "$R"
N=$(grep -cE "Test Case .*(passed|failed)" "$OUT/uitest.log")
[ "$N" -gt 0 ] || { say "  FAIL no selected check ran (wrong name?)"; UT=1; }
say "RESULT selected screen checks: $([ $UT -eq 0 ] && echo ok || echo FAILED)"; say "TIME tests: $((SECONDS-T))s"
grep -E "LAB-NOTE" "$OUT/uitest.log" | sed 's/^.*LAB-NOTE/LAB-NOTE/' | sort -u | head -40 >> "$R" || true
grep -E "^\s+t = |Test Case|error:" "$OUT/uitest.log" | tail -300 > "$OUT/uitest-tail.txt"; rm "$OUT/uitest.log"
for f in "$OUT"/*.png; do [ -f "$f" ] && sips -Z 1300 "$f" >/dev/null 2>&1; done
say "TIME total on the Mac: $((SECONDS-T0))s"
exit $UT
