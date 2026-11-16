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
[ -n "$C" ] && [ -f "$C/Library/Application Support/BikeComputer/store.json" ] && say "  ok   the demo athlete was written inside Lab's own container" || { say "  FAIL no demo athlete record in Lab's container"; FAIL=1; }
if [ $FAIL -ne 0 ]; then xcrun simctl spawn "$SIM" log show --last 3m --style compact --predicate 'process == "CycliftLab"' 2>/dev/null | tail -150 > "$OUT/simlog.txt"; ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i cycliftlab | head -3 | while read f; do head -c 60000 ~/Library/Logs/DiagnosticReports/"$f" > "$OUT/crash-$f.txt"; done; fi
for f in "$OUT"/*.png; do [ -f "$f" ] && sips -Z 1300 "$f" >/dev/null 2>&1; done
say "RESULT Lab launch in six themes: $([ $FAIL -eq 0 ] && echo ok || echo FAILED)"
exit $FAIL
