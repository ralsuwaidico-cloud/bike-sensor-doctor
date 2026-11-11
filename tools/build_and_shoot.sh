#!/bin/bash
# Builds the standalone UI Lab for the simulator and captures screenshots by launching it with LAB_* options.
# Prototype pipeline only — it never touches the production app, its tests, signing or TestFlight.
set -u
OUT="$PWD/out"; mkdir -p "$OUT/shots"
SUM="$OUT/summary.txt"; : > "$SUM"
note() { echo "$*" | tee -a "$SUM"; }
note "Cyclift UI Lab prototype build — $(date -u '+%Y-%m-%d %H:%M UTC') — commit $(git rev-parse --short HEAD 2>/dev/null)"
note "$(sw_vers -productName) $(sw_vers -productVersion), $(xcodebuild -version | tr '\n' ' ')"

python3 tools/contrast_check.py > "$OUT/contrast.txt" 2>&1; note "RESULT contrast: $([ $? -eq 0 ] && echo ok || echo FAILED) — $(tail -1 "$OUT/contrast.txt")"

command -v xcodegen >/dev/null || brew install xcodegen >/dev/null 2>&1
xcodegen generate > "$OUT/xcodegen.txt" 2>&1 || { note "RESULT generate: FAILED"; cat "$OUT/xcodegen.txt" >> "$SUM"; exit 1; }
note "RESULT generate: ok"

xcodebuild -project CycliftUILab.xcodeproj -scheme CycliftUILab -configuration Debug -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build > "$OUT/build.txt" 2>&1
RC=$?
grep -E "error:|warning: unre|BUILD (SUCCEEDED|FAILED)" "$OUT/build.txt" | sed "s#$PWD/##" | sort -u | head -80 > "$OUT/build-digest.txt"
if [ $RC -ne 0 ]; then note "RESULT build: FAILED"; cat "$OUT/build-digest.txt" >> "$SUM"; exit 1; fi
note "RESULT build: ok ($(grep -c 'warning:' "$OUT/build.txt") warnings)"
APP="build/Build/Products/Debug-iphonesimulator/CycliftUILab.app"
BID="lab.cyclift.uilab"

RT=$(xcrun simctl list runtimes available -j | python3 -c "import json,sys; r=[x for x in json.load(sys.stdin)['runtimes'] if x['platform']=='iOS']; print(sorted(r,key=lambda x:[int(p) for p in x['version'].split('.')])[-1]['identifier'])")
mk() { # name, device types… → UDID of the first type that can be created
  local name="$1"; shift
  for T in "$@"; do U=$(xcrun simctl create "$name" "com.apple.CoreSimulator.SimDeviceType.$T" "$RT" 2>/dev/null) && { echo "$U|$T"; return; }; done
}
STD=$(mk "Lab standard" iPhone-17 iPhone-16 iPhone-15)
SMALL=$(mk "Lab small" iPhone-SE-3rd-generation iPhone-16e iPhone-13-mini)
note "Runtime: $RT · standard: ${STD#*|} · small: ${SMALL#*|}"

shoot() { # udid name env…
  local U="$1" NAME="$2"; shift 2
  local ENVV=(); for kv in "$@"; do ENVV+=("SIMCTL_CHILD_$kv"); done
  xcrun simctl terminate "$U" "$BID" >/dev/null 2>&1
  env "${ENVV[@]}" xcrun simctl launch "$U" "$BID" >/dev/null 2>&1 || { note "launch failed: $NAME"; return; }
  sleep "${SETTLE:-3}"
  xcrun simctl io "$U" screenshot "$OUT/shots/$NAME.png" >/dev/null 2>&1 || note "screenshot failed: $NAME"
}
prep() { # udid
  xcrun simctl boot "$1" >/dev/null 2>&1; xcrun simctl bootstatus "$1" -b >/dev/null 2>&1
  xcrun simctl status_bar "$1" override --time "9:41" --batteryState charged --batteryLevel 100 >/dev/null 2>&1
  xcrun simctl install "$1" "$APP" || note "install failed on $1"
  xcrun simctl ui "$1" content_size large >/dev/null 2>&1
}
THEMES="obsidian arctic ocean forest sandstone highContrast"
PAGES="buttons cards rings charts controls sheets"

if [ -n "$STD" ]; then
  U="${STD%|*}"; prep "$U"
  SETTLE=6 shoot "$U" warmup LAB_THEME=obsidian
  for T in $THEMES; do
    shoot "$U" "home-$T-1-top" LAB_THEME=$T LAB_SCENARIO=established
    shoot "$U" "home-$T-2-lower" LAB_THEME=$T LAB_SCENARIO=established LAB_SCROLL=trends
  done
  for T in obsidian arctic; do
    shoot "$U" "state-$T-newuser-1-top" LAB_THEME=$T LAB_SCENARIO=newUser
    shoot "$U" "state-$T-newuser-2-lower" LAB_THEME=$T LAB_SCENARIO=newUser LAB_SCROLL=trends
    shoot "$U" "state-$T-loading" LAB_THEME=$T LAB_SCENARIO=loading
    shoot "$U" "sheet-$T-ring-consistency" LAB_THEME=$T LAB_SHEET=ringConsistency
    shoot "$U" "sheet-$T-ring-load" LAB_THEME=$T LAB_SHEET=ringLoad
    shoot "$U" "sheet-$T-ring-recovery" LAB_THEME=$T LAB_SHEET=ringRecovery
    shoot "$U" "sheet-$T-review" LAB_THEME=$T LAB_SHEET=review
    shoot "$U" "sheet-$T-coach-why" LAB_THEME=$T LAB_SHEET=coachWhy
    shoot "$U" "sheet-$T-day" LAB_THEME=$T LAB_SHEET=day
    shoot "$U" "lab-$T" LAB_THEME=$T LAB_SCREEN=lab
  done
  for T in obsidian arctic highContrast; do
    for P in $PAGES; do shoot "$U" "gallery-$T-$P" LAB_THEME=$T LAB_SCREEN=gallery LAB_PAGE=$P; done
  done
  xcrun simctl ui "$U" content_size accessibility-large >/dev/null 2>&1
  for T in obsidian highContrast; do
    shoot "$U" "a11y-$T-AXL-1-top" LAB_THEME=$T
    shoot "$U" "a11y-$T-AXL-2-lower" LAB_THEME=$T LAB_SCROLL=trends
  done
  xcrun simctl shutdown "$U" >/dev/null 2>&1
fi
if [ -n "$SMALL" ]; then
  U="${SMALL%|*}"; prep "$U"
  SETTLE=6 shoot "$U" warmup-small LAB_THEME=obsidian
  for T in obsidian arctic; do
    shoot "$U" "small-$T-1-top" LAB_THEME=$T
    shoot "$U" "small-$T-2-lower" LAB_THEME=$T LAB_SCROLL=trends
    shoot "$U" "small-$T-newuser" LAB_THEME=$T LAB_SCENARIO=newUser
  done
  xcrun simctl ui "$U" content_size accessibility-large >/dev/null 2>&1
  shoot "$U" "small-obsidian-AXL-1-top" LAB_THEME=obsidian
  shoot "$U" "small-obsidian-AXL-2-lower" LAB_THEME=obsidian LAB_SCROLL=trends
  xcrun simctl shutdown "$U" >/dev/null 2>&1
fi
rm -f "$OUT/shots/warmup.png" "$OUT/shots/warmup-small.png"
note "RESULT screenshots: $(ls "$OUT/shots" | wc -l | tr -d ' ') files"
exit 0
