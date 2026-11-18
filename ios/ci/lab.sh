#!/bin/bash
# Cyclift Lab: simulator build + isolation report + one Home screenshot per theme. No signing, no upload.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="$PWD/build/lab-out"; rm -rf "$OUT"; mkdir -p "$OUT" build/lab-gen
R="$OUT/REPORT.txt"; say() { echo "$*" | tee -a "$R"; }
BID=com.ralsuwaidico.cycliftlab
command -v xcodegen >/dev/null || brew install xcodegen >/dev/null 2>&1
xcodegen generate --spec project-lab.yml > "$OUT/xcodegen.txt" 2>&1 || { say "RESULT generate: FAILED"; tail -20 "$OUT/xcodegen.txt"; exit 1; }
T=$SECONDS
xcodebuild build -project CycliftLab.xcodeproj -scheme CycliftLab -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/lab-dd -clonedSourcePackagesDirPath build/spm CODE_SIGNING_ALLOWED=NO > "$OUT/build.log" 2>&1
if [ $? -ne 0 ]; then say "RESULT Lab build: FAILED · $((SECONDS-T))s"; grep -E " error: " "$OUT/build.log" | sed -E 's#.*/ios/##' | sort -u | head -40 | tee -a "$R"; tail -c 200000 "$OUT/build.log" > "$OUT/build-tail.log"; rm "$OUT/build.log"; exit 1; fi
say "RESULT Lab build: ok · $((SECONDS-T))s"; rm "$OUT/build.log"
APP=build/lab-dd/Build/Products/Debug-iphonesimulator/CycliftLab.app
plutil -convert json -o "$OUT/Info.json" "$APP/Info.plist"
python3 - "$OUT/Info.json" "$APP" <<'PY' | tee -a "$R"
import json, os, sys
info = json.load(open(sys.argv[1])); app = sys.argv[2]; bad = 0
def check(ok, text):
    global bad
    print(("  ok   " if ok else "  FAIL ") + text); bad += 0 if ok else 1
print("ISOLATION (from the built app)")
check(info.get("CFBundleIdentifier") == "com.ralsuwaidico.cycliftlab", "app identity is com.ralsuwaidico.cycliftlab: " + str(info.get("CFBundleIdentifier")))
check(info.get("CFBundleDisplayName") == "Cyclift Lab", "name on the phone is Cyclift Lab")
for k in ["NSBluetoothAlwaysUsageDescription", "NSBluetoothPeripheralUsageDescription", "NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription",
          "UIBackgroundModes", "CFBundleURLTypes", "SUPABASE_URL", "SUPABASE_ANON_KEY", "GOOGLE_WEB_CLIENT_ID", "GOOGLE_IOS_CLIENT_ID", "CYCLIFT_SUPPORT_EMAIL"]:
    check(k not in info, "absent: " + k)
check(not os.path.exists(os.path.join(app, "Watch")), "no Apple Watch app inside")
icon = ((info.get("CFBundleIcons") or {}).get("CFBundlePrimaryIcon") or {}).get("CFBundleIconName")
check(icon == "AppIconLab", "its own icon (AppIconLab): " + str(icon))
check(not any(f.endswith(".entitlements") or f == "archived-expanded-entitlements.xcent" for f in os.listdir(app)), "no entitlements file in the app")
print("ISOLATION RESULT: " + ("ok" if bad == 0 else f"FAILED ({bad})"))
sys.exit(1 if bad else 0)
PY
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
grep -c "CYCLIFT_LAB" project.yml > /dev/null && { say "  FAIL the production project file mentions CYCLIFT_LAB"; exit 1; } || say "  ok   the production project file does not enable Lab"

SIM=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]; best=None
for rt,devs in d.items():
    if ".iOS-" not in rt: continue
    ver=tuple(int(x) for x in rt.split(".iOS-")[1].split("-"))
    for x in devs:
        if x["name"].startswith("iPhone") and "SE" not in x["name"] and (best is None or ver>best[0]): best=(ver,x["udid"],x["name"])
print(best[1] if best else "")')
[ -n "$SIM" ] || { say "RESULT Lab launch: no simulator"; exit 1; }
xcrun simctl boot "$SIM" >/dev/null 2>&1; xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1
xcrun simctl install "$SIM" "$APP" || { say "RESULT Lab install: FAILED"; exit 1; }
FAIL=0; N=0
for t in obsidian arctic ocean forest sandstone highContrast; do
  N=$((N+1))
  xcrun simctl terminate "$SIM" $BID >/dev/null 2>&1
  SIMCTL_CHILD_LAB_THEME=$t xcrun simctl launch "$SIM" $BID > "$OUT/launch-$t.txt" 2>&1
  sleep 14
  if pgrep -f "CycliftLab.app/CycliftLab" >/dev/null; then xcrun simctl io "$SIM" screenshot "$OUT/lab-$N-$t-home.png" >/dev/null 2>&1; say "  $t: running, screenshot taken"
  else say "  $t: NOT RUNNING 14 s after launch (crash?)"; FAIL=1; fi
done
C=$(xcrun simctl get_app_container "$SIM" $BID data 2>/dev/null)
STORE="$C/Library/Application Support/BikeComputer/store.json"
[ -n "$C" ] && [ -f "$STORE" ] && say "  ok   the demo athlete was written inside Lab's own container" || { say "  FAIL no demo athlete record in Lab's container"; FAIL=1; }
case "$C" in *"$BID"*|*/Containers/Data/Application/*) say "  ok   container: .../Containers/Data/Application/<Lab only>";; *) say "  FAIL unexpected container path"; FAIL=1;; esac
# relaunch keeps the same demo record (it is seeded once, never regenerated over an existing one)
first() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["profile"]["name"], d["plan"][0]["id"], len(d.get("strength",[])))' "$STORE" 2>/dev/null; }
A=$(first); xcrun simctl terminate "$SIM" $BID >/dev/null 2>&1; xcrun simctl launch "$SIM" $BID >/dev/null 2>&1; sleep 10; B=$(first)
[ -n "$A" ] && [ "$A" = "$B" ] && say "  ok   relaunch kept the same demo record" || { say "  FAIL the demo record changed on relaunch ($A / $B)"; FAIL=1; }
# largest text size, one dark and one light theme
for t in obsidian arctic; do
  xcrun simctl terminate "$SIM" $BID >/dev/null 2>&1
  SIMCTL_CHILD_LAB_THEME=$t xcrun simctl launch "$SIM" $BID -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXL >/dev/null 2>&1; sleep 14
  pgrep -f "CycliftLab.app/CycliftLab" >/dev/null && { xcrun simctl io "$SIM" screenshot "$OUT/lab-ax3-$t-home.png" >/dev/null 2>&1; say "  $t at the largest text size: running, screenshot taken"; } || { say "  $t at the largest text size: NOT RUNNING"; FAIL=1; }
done
if [ $FAIL -ne 0 ]; then xcrun simctl spawn "$SIM" log show --last 3m --style compact --predicate 'process == "CycliftLab"' 2>/dev/null | tail -150 > "$OUT/simlog.txt"; ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i cycliftlab | head -3 | while read f; do head -c 60000 ~/Library/Logs/DiagnosticReports/"$f" > "$OUT/crash-$f.txt"; done; fi
# ---- "Follow iOS": one running app, iOS switched from light to dark and back; the picture must change each time
xcrun simctl terminate "$SIM" $BID >/dev/null 2>&1
xcrun simctl ui "$SIM" appearance light >/dev/null 2>&1
SIMCTL_CHILD_LAB_THEME=system xcrun simctl launch "$SIM" $BID >/dev/null 2>&1; sleep 14
P_A=$(pgrep -f "CycliftLab.app/CycliftLab" | head -1)
xcrun simctl io "$SIM" screenshot "$OUT/lab-system-1-ios-light.png" >/dev/null 2>&1
xcrun simctl ui "$SIM" appearance dark >/dev/null 2>&1; sleep 6
xcrun simctl io "$SIM" screenshot "$OUT/lab-system-2-ios-dark.png" >/dev/null 2>&1
xcrun simctl ui "$SIM" appearance light >/dev/null 2>&1; sleep 6
xcrun simctl io "$SIM" screenshot "$OUT/lab-system-3-ios-light-again.png" >/dev/null 2>&1
P_B=$(pgrep -f "CycliftLab.app/CycliftLab" | head -1)
# The three pictures are published; whether iOS-light shows the light theme and iOS-dark the dark one is judged by eye.
# Here only: all three were taken and the dark one is not the same picture as the light ones.
if [ -s "$OUT/lab-system-1-ios-light.png" ] && [ -s "$OUT/lab-system-2-ios-dark.png" ] && [ -s "$OUT/lab-system-3-ios-light-again.png" ] \
   && ! cmp -s "$OUT/lab-system-1-ios-light.png" "$OUT/lab-system-2-ios-dark.png" && ! cmp -s "$OUT/lab-system-2-ios-dark.png" "$OUT/lab-system-3-ios-light-again.png"; then
  say "  Follow iOS: three screenshots taken (iOS light, dark, light again) — to be inspected"
else say "  FAIL Follow iOS: screenshots missing or identical"; FAIL=1; fi
[ -n "$P_A" ] && [ "$P_A" = "$P_B" ] && say "  ok   the app was not relaunched during the iOS light/dark changes" || { say "  FAIL the app did not keep running through the iOS light/dark changes ($P_A / $P_B)"; FAIL=1; }

# ---- Lab screen checks (five screens x six themes, switching without relaunch, delete all data) with the PRODUCTION
# app installed beside Lab: its files must be byte-for-byte the same afterwards.
PBID=com.ralsuwaidico.bikecomputer
xcodegen generate --spec project.yml > "$OUT/xcodegen-production.txt" 2>&1
xcodebuild build -project BikeComputer.xcodeproj -scheme BikeComputer -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/prod-dd -clonedSourcePackagesDirPath build/spm CODE_SIGNING_ALLOWED=NO > "$OUT/build-production.log" 2>&1
if [ $? -eq 0 ]; then
  rm "$OUT/build-production.log"
  xcrun simctl install "$SIM" build/prod-dd/Build/Products/Debug-iphonesimulator/BikeComputer.app
  SIMCTL_CHILD_BC_UITEST_RESET=1 xcrun simctl launch "$SIM" $PBID >/dev/null 2>&1; sleep 12; xcrun simctl terminate "$SIM" $PBID >/dev/null 2>&1; sleep 2
  PC=$(xcrun simctl get_app_container "$SIM" $PBID data 2>/dev/null)
  phash() { (cd "$PC/Library" 2>/dev/null && find "Application Support" Preferences -type f 2>/dev/null | sort | xargs shasum 2>/dev/null | shasum | cut -c1-16; find "Application Support" Preferences -type f 2>/dev/null | wc -l | tr -d ' '); }
  P1=$(phash | tr '\n' ' '); say "  production app installed beside Lab: files fingerprint $P1"
else say "  FAIL the production app did not build for the side-by-side check"; grep -E " error: " "$OUT/build-production.log" | sort -u | head -10 | tee -a "$R"; FAIL=1; P1=""; fi
xcodegen generate --spec project-lab.yml >> "$OUT/xcodegen.txt" 2>&1
T=$SECONDS
TEST_RUNNER_LAYOUT_DIR="$OUT" xcodebuild test -project CycliftLab.xcodeproj -scheme CycliftLab -configuration Debug -destination "id=$SIM" \
  -derivedDataPath build/lab-dd -clonedSourcePackagesDirPath build/spm -skip-testing:CycliftLabUITests/LabFast CODE_SIGNING_ALLOWED=NO > "$OUT/uitest.log" 2>&1
UT=$?
grep -E "Test Case .*(passed|failed)|error: |Executed [0-9]+ tests" "$OUT/uitest.log" | sed -E 's#.*/ios/##' | sort -u | cut -c1-400 | tee -a "$R"
say "RESULT Lab screen checks: $([ $UT -eq 0 ] && echo ok || echo FAILED) · $((SECONDS-T))s"; [ $UT -eq 0 ] || FAIL=1
# measurements the checks print on purpose (dock position, end-of-page clearance, where the Coach card led) go into the report
grep -E "LAB-NOTE" "$OUT/uitest.log" | sed 's/^.*LAB-NOTE/LAB-NOTE/' | sort -u | head -40 >> "$R" || true
grep -E "^\s+t = |Test Case|error:" "$OUT/uitest.log" | tail -400 > "$OUT/uitest-tail.txt"; rm "$OUT/uitest.log"
if [ -n "$P1" ]; then P2=$(phash | tr '\n' ' '); [ "$P1" = "$P2" ] && say "  ok   the production app's files are unchanged after every Lab check, including Lab's Delete all data ($P2)" || { say "  FAIL the production app's files changed ($P1 -> $P2)"; FAIL=1; }; fi
for f in "$OUT"/*.png; do [ -f "$f" ] && sips -Z 1300 "$f" >/dev/null 2>&1; done
say "RESULT Lab launch in six themes: $([ $FAIL -eq 0 ] && echo ok || echo FAILED)"
exit $FAIL
