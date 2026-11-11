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
PAGES="home21 buttons cards rings charts controls sheets"
SETTLE=2.5

full() { # udid name env… → full-length Home image rendered by the prototype itself
  local U="$1" NAME="$2"; shift 2
  local C; C=$(xcrun simctl get_app_container "$U" "$BID" data 2>/dev/null)
  [ -n "$C" ] && rm -f "$C/Documents/home-full.png"
  SETTLE=4.5 shoot "$U" "zz-render-tmp" LAB_RENDER=1 "$@"
  rm -f "$OUT/shots/zz-render-tmp.png"
  if [ -n "$C" ] && [ -f "$C/Documents/home-full.png" ]; then cp "$C/Documents/home-full.png" "$OUT/full/$NAME.png"; else note "full-length render missing: $NAME"; fi
}
mkdir -p "$OUT/full"

if [ -n "$STD" ]; then
  U="${STD%|*}"; prep "$U"
  SETTLE=6 shoot "$U" warmup LAB_THEME=obsidian
  for T in $THEMES; do
    shoot "$U" "home-$T-1-top" LAB_THEME=$T
    shoot "$U" "home-$T-2-cards" LAB_THEME=$T LAB_SCROLL=cards
    shoot "$U" "home-$T-3-trends" LAB_THEME=$T LAB_SCROLL=trends LAB_SELECT=2
    shoot "$U" "home-$T-4-metrics" LAB_THEME=$T LAB_SCROLL=metrics
    full "$U" "full-$T" LAB_THEME=$T LAB_SELECT=2
  done
  for T in obsidian arctic; do
    for S in newUser cyclingOnly strengthOnly noPlan partialData longName loading; do
      shoot "$U" "state-$T-$S-1-top" LAB_THEME=$T LAB_SCENARIO=$S
      full "$U" "full-$T-$S" LAB_THEME=$T LAB_SCENARIO=$S
    done
    shoot "$U" "state-$T-newUser-2-trends" LAB_THEME=$T LAB_SCENARIO=newUser LAB_SCROLL=trends
    for SH in mix sleep consistency recovery review; do shoot "$U" "sheet-$T-$SH" LAB_THEME=$T LAB_SHEET=$SH; done
  done
  for SH in day endurance strength coachWhy trendsInfo trendDay metric profile hub; do shoot "$U" "sheet-obsidian-$SH" LAB_THEME=obsidian LAB_SHEET=$SH; done
  shoot "$U" "sheet-obsidian-mix-cyclingOnly" LAB_THEME=obsidian LAB_SCENARIO=cyclingOnly LAB_SHEET=mix
  shoot "$U" "sheet-obsidian-sleep-nodata" LAB_THEME=obsidian LAB_SCENARIO=partialData LAB_SHEET=sleep
  shoot "$U" "sheet-obsidian-recovery-partial" LAB_THEME=obsidian LAB_SCENARIO=partialData LAB_SHEET=recovery
  for D in postponed accepted declined; do shoot "$U" "coach-obsidian-$D" LAB_THEME=obsidian LAB_SCROLL=cards LAB_DECISION=$D; done
  shoot "$U" "nav-obsidian-plan" LAB_THEME=obsidian LAB_SCREEN=plan
  shoot "$U" "nav-arctic-profile-lab" LAB_THEME=arctic LAB_SCREEN=lab
  for T in obsidian arctic highContrast; do
    for P in $PAGES; do shoot "$U" "gallery-$T-$P" LAB_THEME=$T LAB_SCREEN=gallery LAB_PAGE=$P; done
  done
  xcrun simctl ui "$U" content_size accessibility-large >/dev/null 2>&1
  for T in obsidian highContrast; do
    shoot "$U" "a11y-$T-AXL-1-top" LAB_THEME=$T
    shoot "$U" "a11y-$T-AXL-2-cards" LAB_THEME=$T LAB_SCROLL=cards
    shoot "$U" "a11y-$T-AXL-3-trends" LAB_THEME=$T LAB_SCROLL=trends LAB_SELECT=2
    full "$U" "full-$T-AXL" LAB_THEME=$T LAB_SELECT=2
  done
  xcrun simctl shutdown "$U" >/dev/null 2>&1
fi
if [ -n "$SMALL" ]; then
  U="${SMALL%|*}"; prep "$U"
  SETTLE=6 shoot "$U" warmup-small LAB_THEME=obsidian
  for T in obsidian arctic; do
    shoot "$U" "small-$T-1-top" LAB_THEME=$T
    shoot "$U" "small-$T-2-cards" LAB_THEME=$T LAB_SCROLL=cards
    shoot "$U" "small-$T-3-trends" LAB_THEME=$T LAB_SCROLL=trends LAB_SELECT=2
    shoot "$U" "small-$T-4-metrics" LAB_THEME=$T LAB_SCROLL=metrics
    full "$U" "full-small-$T" LAB_THEME=$T LAB_SELECT=2
  done
  shoot "$U" "small-obsidian-newUser" LAB_THEME=obsidian LAB_SCENARIO=newUser
  shoot "$U" "small-obsidian-longName" LAB_THEME=obsidian LAB_SCENARIO=longName
  full "$U" "full-small-obsidian-newUser" LAB_THEME=obsidian LAB_SCENARIO=newUser
  xcrun simctl ui "$U" content_size accessibility-large >/dev/null 2>&1
  shoot "$U" "small-obsidian-AXL-1-top" LAB_THEME=obsidian
  shoot "$U" "small-obsidian-AXL-3-trends" LAB_THEME=obsidian LAB_SCROLL=trends LAB_SELECT=2
  full "$U" "full-small-obsidian-AXL" LAB_THEME=obsidian LAB_SELECT=2
  xcrun simctl shutdown "$U" >/dev/null 2>&1
fi
rm -f "$OUT/shots/warmup.png" "$OUT/shots/warmup-small.png"
note "RESULT screenshots: $(ls "$OUT/shots" | wc -l | tr -d ' ') screen files, $(ls "$OUT/full" | wc -l | tr -d ' ') full-length files"
exit 0
