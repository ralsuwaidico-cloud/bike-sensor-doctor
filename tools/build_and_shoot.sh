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
# "[compile-only]" in the commit subject: also compile the interaction tests, then stop (fast check; proves nothing at runtime)
if git log -1 --format=%s 2>/dev/null | grep -q "\[compile-only\]"; then
  xcodebuild build-for-testing -project CycliftUILab.xcodeproj -scheme CycliftUILab -sdk iphonesimulator \
    -destination "generic/platform=iOS Simulator" -derivedDataPath build CODE_SIGNING_ALLOWED=NO > "$OUT/build-tests.txt" 2>&1
  RC=$?
  grep -E "error:|TEST BUILD (SUCCEEDED|FAILED)" "$OUT/build-tests.txt" | sed "s#$PWD/##" | sort -u | head -60 >> "$OUT/build-digest.txt"
  note "RESULT test compile: $([ $RC -eq 0 ] && echo ok || echo FAILED)"; [ $RC -ne 0 ] && grep "error:" "$OUT/build-digest.txt" >> "$SUM"
  note "COMPILE-ONLY run: nothing was launched, tested or captured."
  exit 0
fi
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
  # "[full-only]" in the commit subject: only the full-length review images are regenerated (no tests, no screen shots)
  if [ -n "$FULL_ONLY" ] && [ "$NAME" != "zz-render-tmp" ] && [ "${NAME#warmup}" = "$NAME" ]; then return; fi
  local ENVV=(); for kv in "$@"; do ENVV+=("SIMCTL_CHILD_$kv"); done
  xcrun simctl terminate "$U" "$BID" >/dev/null 2>&1
  env "${ENVV[@]}" xcrun simctl launch "$U" "$BID" >/dev/null 2>&1 || { note "launch failed: $NAME"; return; }
  sleep "${SETTLE:-3}"
  xcrun simctl io "$U" screenshot "$OUT/shots/$NAME.png" >/dev/null 2>&1 || note "screenshot failed: $NAME"
  # a blank frame (app not drawn yet) compresses to a very small file: retake once after a longer wait
  if [ -f "$OUT/shots/$NAME.png" ] && [ "$(stat -f%z "$OUT/shots/$NAME.png")" -lt 100000 ] && [ "$NAME" != "zz-render-tmp" ]; then
    sleep 4; xcrun simctl io "$U" screenshot "$OUT/shots/$NAME.png" >/dev/null 2>&1; note "retaken (blank frame): $NAME"
  fi
}
prep() { # udid
  xcrun simctl boot "$1" >/dev/null 2>&1; xcrun simctl bootstatus "$1" -b >/dev/null 2>&1
  xcrun simctl status_bar "$1" override --time "9:41" --batteryState charged --batteryLevel 100 >/dev/null 2>&1
  xcrun simctl install "$1" "$APP" || note "install failed on $1"
  xcrun simctl ui "$1" content_size large >/dev/null 2>&1
}
THEMES="obsidian arctic ocean forest sandstone highContrast"
SETTLE=2.5

full() { # udid name env… → full-length Home image rendered by the prototype itself
  local U="$1" NAME="$2"; shift 2
  local C; C=$(xcrun simctl get_app_container "$U" "$BID" data 2>/dev/null)
  [ -n "$C" ] && rm -f "$C/Documents/home-full.png"
  SETTLE=4.5 shoot "$U" "zz-render-tmp" LAB_RENDER=1 "$@"
  rm -f "$OUT/shots/zz-render-tmp.png"
  if [ -n "$C" ] && [ ! -f "$C/Documents/home-full.png" ]; then   # slow launch: try once more with a longer wait
    SETTLE=9 shoot "$U" "zz-render-tmp" LAB_RENDER=1 "$@"; rm -f "$OUT/shots/zz-render-tmp.png"
  fi
  if [ -n "$C" ] && [ -f "$C/Documents/home-full.png" ]; then cp "$C/Documents/home-full.png" "$OUT/full/$NAME.png"; else note "full-length render missing: $NAME"; fi
}
mkdir -p "$OUT/full"

# ---- Interaction tests (prototype only). Written to out/interaction-tests.txt; a failure is reported, never hidden.
TESTS="$OUT/interaction-tests.txt"; : > "$TESTS"
echo "Cyclift UI Lab — Home v2.3 interaction tests (PROTOTYPE, iOS Simulator, sample data)." >> "$TESTS"
echo "A pass here is not validation of the production app and not a real-device test." >> "$TESTS"
runtests() { # udid label
  local U="$1" L="$2" LOG="$OUT/test-$2.txt"
  xcrun simctl boot "$U" >/dev/null 2>&1; xcrun simctl bootstatus "$U" -b >/dev/null 2>&1
  xcrun simctl ui "$U" content_size large >/dev/null 2>&1
  xcodebuild test -project CycliftUILab.xcodeproj -scheme CycliftUILab -destination "id=$U" -derivedDataPath build \
    -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO ${ONLY_TESTING:+-only-testing:$ONLY_TESTING} > "$LOG" 2>&1
  local RC=$?
  local P F
  P=$(grep -cE "^Test Case .* passed" "$LOG"); F=$(grep -cE "^Test Case .* failed" "$LOG")
  { echo; echo "== $L (${3}) — passed $P, failed $F, xcodebuild exit $RC ==";
    grep -E "^Test Case .* (passed|failed)" "$LOG" | sed -E "s/^Test Case '-\[CycliftUILabUITests\.[A-Za-z0-9_]+ (.*)\]' (passed|failed) \((.*) seconds\)\./  \2  \1  (\3 s)/";
    echo "-- observations written by the tests --"; grep -hE "LABNOTE" "$LOG" | sed -E "s/^.*LABNOTE /  /" | sort -u;
    if [ "$F" != "0" ] || [ $RC -ne 0 ]; then echo "-- failure details --"; grep -E "error:|Testing failed|\*\* TEST" "$LOG" | sed "s#$PWD/##" | sort -u | head -60; fi; } >> "$TESTS"
  note "RESULT interaction tests ($L): passed $P, failed $F$([ $RC -ne 0 ] && [ "$F" = "0" ] && echo " — xcodebuild exit $RC (see interaction-tests.txt)")"
  # keep the tail of the raw log small enough to publish
  tail -c 400000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
}
# ---- Plan v2.0 visual round 1 (branch proto/ui-lab-plan): Plan tests and Plan screens only. Home is not re-run here.
PLAN_MODE=1
FULL_ONLY=""
if [ -n "$PLAN_MODE" ]; then
  sed -i '' '1,2d' "$TESTS" 2>/dev/null
  { echo "Cyclift UI Lab — Plan v2.0 visual round 1, interaction and layout tests (PROTOTYPE, iOS Simulator, sample data)."; echo "A pass here is not validation of the production app and not a real-device test."; } >> "$TESTS"
  ONLY_TESTING="CycliftUILabUITests/PlanInteractionTests"
  [ -n "$STD" ] && runtests "${STD%|*}" standard "${STD#*|}"
  [ -n "$SMALL" ] && runtests "${SMALL%|*}" small "${SMALL#*|}"
  planshots() { # udid prefix
    local U="$1" P="$2"
    for T in $THEMES; do
      shoot "$U" "$P-$T-weekly" LAB_SCREEN=plan LAB_THEME=$T
      shoot "$U" "$P-$T-recurring" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN_SECTION=recurring
    done
    for T in obsidian arctic; do
      shoot "$U" "$P-$T-state-no-suggestion" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN=noSuggestion
      shoot "$U" "$P-$T-state-one-session" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN_DAY=10
      shoot "$U" "$P-$T-state-missed" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN_DAY=9
      shoot "$U" "$P-$T-state-rescheduled" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN_DAY=13
      shoot "$U" "$P-$T-state-empty-day" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN_DAY=15
      shoot "$U" "$P-$T-state-rest-day" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN_DAY=20
      shoot "$U" "$P-$T-state-no-goal" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN=noGoal
      shoot "$U" "$P-$T-state-budget-conflict" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN=budget LAB_PLAN_SECTION=recurring
      shoot "$U" "$P-$T-state-no-goal-recurring" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN=noGoal LAB_PLAN_SECTION=recurring
      shoot "$U" "$P-$T-variantA-cards-four" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN=busy
      shoot "$U" "$P-$T-variantB-hybrid-four" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN=busy LAB_PLAN_CARDS=hybrid
      shoot "$U" "$P-$T-variantB-hybrid-two" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN_CARDS=hybrid
    done
    xcrun simctl ui "$U" content_size accessibility-large >/dev/null 2>&1
    for T in obsidian highContrast; do
      shoot "$U" "$P-$T-AXL-weekly" LAB_SCREEN=plan LAB_THEME=$T
      shoot "$U" "$P-$T-AXL-recurring" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN_SECTION=recurring
      shoot "$U" "$P-$T-AXL-variantB-hybrid" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN_CARDS=hybrid
      shoot "$U" "$P-$T-AXL-no-goal" LAB_SCREEN=plan LAB_THEME=$T LAB_PLAN=noGoal
    done
    xcrun simctl ui "$U" content_size large >/dev/null 2>&1
  }
  if [ -n "$STD" ]; then U="${STD%|*}"; prep "$U"; SETTLE=6 shoot "$U" warmup LAB_THEME=obsidian LAB_SCREEN=plan; planshots "$U" plan-std; xcrun simctl shutdown "$U" >/dev/null 2>&1; fi
  if [ -n "$SMALL" ]; then U="${SMALL%|*}"; prep "$U"; SETTLE=4; SETTLE=6 shoot "$U" warmup-small LAB_THEME=obsidian LAB_SCREEN=plan; planshots "$U" plan-small; xcrun simctl shutdown "$U" >/dev/null 2>&1; fi
  rm -f "$OUT/shots/warmup.png" "$OUT/shots/warmup-small.png"
  note "PLAN run: Plan tests and Plan screens only (Home was not re-run on this branch)."
  note "Screens captured: $(ls "$OUT/shots" 2>/dev/null | wc -l | tr -d ' ')"
  exit 0
fi
FULL_ONLY=""; git log -1 --format=%s 2>/dev/null | grep -q "\[full-only\]" && FULL_ONLY=1
[ -n "$FULL_ONLY" ] && { note "FULL-ONLY run: interaction tests and screen captures were skipped on purpose; see the previous run for them"; echo "Not run in this full-only build." >> "$TESTS"; }
[ -z "$FULL_ONLY" ] && [ -n "$STD" ] && runtests "${STD%|*}" standard "${STD#*|}"
[ -z "$FULL_ONLY" ] && [ -n "$SMALL" ] && runtests "${SMALL%|*}" small "${SMALL#*|}"

if [ -n "$STD" ]; then
  U="${STD%|*}"; prep "$U"
  SETTLE=6 shoot "$U" warmup LAB_THEME=obsidian
  for T in $THEMES; do
    shoot "$U" "home-$T-1-top" LAB_THEME=$T
    shoot "$U" "home-$T-2-cards" LAB_THEME=$T LAB_SCROLL=cards
    shoot "$U" "home-$T-3-graph" LAB_THEME=$T LAB_SCROLL=trends LAB_SELECT=6
    shoot "$U" "home-$T-4-metrics" LAB_THEME=$T LAB_SCROLL=metrics
    full "$U" "full-$T" LAB_THEME=$T
  done
  for T in obsidian arctic; do
    shoot "$U" "graph-$T-recovery-7d-noselection" LAB_THEME=$T LAB_SCROLL=trends
    shoot "$U" "graph-$T-recovery-4w" LAB_THEME=$T LAB_SCROLL=trends LAB_GRAPH_RANGE=4w LAB_SELECT=20
    shoot "$U" "graph-$T-activity-7d" LAB_THEME=$T LAB_SCROLL=trends LAB_GRAPH_MODE=activity LAB_SELECT=2
    shoot "$U" "graph-$T-activity-4w" LAB_THEME=$T LAB_SCROLL=trends LAB_GRAPH_MODE=activity LAB_GRAPH_RANGE=4w LAB_SELECT=16
    shoot "$U" "graph-$T-trends-7d" LAB_THEME=$T LAB_SCROLL=trends LAB_GRAPH_MODE=trends LAB_SELECT=5
    shoot "$U" "graph-$T-trends-4w-gaps" LAB_THEME=$T LAB_SCROLL=trends LAB_GRAPH_MODE=trends LAB_GRAPH_RANGE=4w LAB_SELECT=23
  done
  shoot "$U" "graph-highContrast-activity-4w" LAB_THEME=highContrast LAB_SCROLL=trends LAB_GRAPH_MODE=activity LAB_GRAPH_RANGE=4w LAB_SELECT=16
  for S in qualitativeRecovery newUser cyclingOnly strengthOnly noPlan noRecovery partialData noSleep longName loading; do
    shoot "$U" "state-obsidian-$S-1-top" LAB_THEME=obsidian LAB_SCENARIO=$S
    full "$U" "full-obsidian-$S" LAB_THEME=obsidian LAB_SCENARIO=$S
  done
  for S in qualitativeRecovery newUser noRecovery; do shoot "$U" "state-arctic-$S-1-top" LAB_THEME=arctic LAB_SCENARIO=$S; done
  shoot "$U" "state-obsidian-newUser-2-graph" LAB_THEME=obsidian LAB_SCENARIO=newUser LAB_SCROLL=trends
  shoot "$U" "state-obsidian-noRecovery-2-graph" LAB_THEME=obsidian LAB_SCENARIO=noRecovery LAB_SCROLL=trends LAB_GRAPH_MODE=trends
  shoot "$U" "state-obsidian-qualitativeRecovery-2-graph" LAB_THEME=obsidian LAB_SCENARIO=qualitativeRecovery LAB_SCROLL=trends LAB_SELECT=5
  for T in obsidian arctic; do
    for SH in mix recovery sleep consistency; do shoot "$U" "sheet-$T-$SH" LAB_THEME=$T LAB_SHEET=$SH; done
  done
  for SH in day endurance strength trendsInfo metric profile hub; do shoot "$U" "sheet-obsidian-$SH" LAB_THEME=obsidian LAB_SHEET=$SH; done
  shoot "$U" "sheet-obsidian-mix-cyclingOnly" LAB_THEME=obsidian LAB_SCENARIO=cyclingOnly LAB_SHEET=mix
  shoot "$U" "sheet-obsidian-mix-newUser" LAB_THEME=obsidian LAB_SCENARIO=newUser LAB_SHEET=mix
  shoot "$U" "sheet-obsidian-recovery-qualitative" LAB_THEME=obsidian LAB_SCENARIO=qualitativeRecovery LAB_SHEET=recovery
  shoot "$U" "sheet-obsidian-recovery-partial" LAB_THEME=obsidian LAB_SCENARIO=partialData LAB_SHEET=recovery
  shoot "$U" "sheet-obsidian-recovery-none" LAB_THEME=obsidian LAB_SCENARIO=noRecovery LAB_SHEET=recovery
  shoot "$U" "sheet-obsidian-sleep-nodata" LAB_THEME=obsidian LAB_SCENARIO=noSleep LAB_SHEET=sleep
  # Coach: compact preview on Home, conversation timeline, proposal detail, decision states
  for T in $THEMES; do shoot "$U" "coach-$T-conversation" LAB_THEME=$T LAB_SCREEN=coach; done
  shoot "$U" "coach-obsidian-conversation-oldest" LAB_THEME=obsidian LAB_SCREEN=coach LAB_SCROLL=top
  for T in obsidian arctic; do shoot "$U" "coach-$T-proposal" LAB_THEME=$T LAB_SCREEN=coach LAB_SHEET=proposal; done
  shoot "$U" "coach-obsidian-proposal-closed" LAB_THEME=obsidian LAB_SCREEN=coach LAB_SHEET=proposalClosed
  for D in postponed accepted declined; do
    shoot "$U" "coach-obsidian-$D-conversation" LAB_THEME=obsidian LAB_SCREEN=coach LAB_DECISION=$D
    shoot "$U" "coach-obsidian-$D-home" LAB_THEME=obsidian LAB_SCROLL=cards LAB_DECISION=$D
  done
  shoot "$U" "coach-obsidian-newUser-conversation" LAB_THEME=obsidian LAB_SCREEN=coach LAB_SCENARIO=newUser
  shoot "$U" "nav-obsidian-plan" LAB_THEME=obsidian LAB_SCREEN=plan
  shoot "$U" "nav-arctic-profile-lab" LAB_THEME=arctic LAB_SCREEN=lab
  for T in obsidian arctic highContrast; do shoot "$U" "gallery-$T-home21" LAB_THEME=$T LAB_SCREEN=gallery LAB_PAGE=home21; done
  xcrun simctl ui "$U" content_size accessibility-large >/dev/null 2>&1
  for T in obsidian highContrast; do
    shoot "$U" "a11y-$T-AXL-1-top" LAB_THEME=$T
    shoot "$U" "a11y-$T-AXL-2-cards" LAB_THEME=$T LAB_SCROLL=cards
    shoot "$U" "a11y-$T-AXL-3-graph" LAB_THEME=$T LAB_SCROLL=trends LAB_SELECT=6
    shoot "$U" "a11y-$T-AXL-4-coach" LAB_THEME=$T LAB_SCREEN=coach
    full "$U" "full-$T-AXL" LAB_THEME=$T
  done
  xcrun simctl shutdown "$U" >/dev/null 2>&1
fi
if [ -n "$SMALL" ]; then
  U="${SMALL%|*}"; prep "$U"; SETTLE=4
  SETTLE=6 shoot "$U" warmup-small LAB_THEME=obsidian
  for T in obsidian arctic; do
    shoot "$U" "small-$T-1-top" LAB_THEME=$T
    shoot "$U" "small-$T-2-cards" LAB_THEME=$T LAB_SCROLL=cards
    shoot "$U" "small-$T-3-graph" LAB_THEME=$T LAB_SCROLL=trends LAB_SELECT=6
    shoot "$U" "small-$T-4-metrics" LAB_THEME=$T LAB_SCROLL=metrics
    full "$U" "full-small-$T" LAB_THEME=$T
  done
  shoot "$U" "small-obsidian-graph-activity-4w" LAB_THEME=obsidian LAB_SCROLL=trends LAB_GRAPH_MODE=activity LAB_GRAPH_RANGE=4w LAB_SELECT=16
  shoot "$U" "small-obsidian-graph-trends" LAB_THEME=obsidian LAB_SCROLL=trends LAB_GRAPH_MODE=trends LAB_SELECT=5
  shoot "$U" "small-obsidian-newUser" LAB_THEME=obsidian LAB_SCENARIO=newUser
  shoot "$U" "small-obsidian-longName" LAB_THEME=obsidian LAB_SCENARIO=longName
  shoot "$U" "small-obsidian-coach-conversation" LAB_THEME=obsidian LAB_SCREEN=coach
  shoot "$U" "small-obsidian-coach-proposal" LAB_THEME=obsidian LAB_SCREEN=coach LAB_SHEET=proposal
  shoot "$U" "small-obsidian-sheet-recovery" LAB_THEME=obsidian LAB_SHEET=recovery
  shoot "$U" "small-obsidian-sheet-mix" LAB_THEME=obsidian LAB_SHEET=mix
  full "$U" "full-small-obsidian-newUser" LAB_THEME=obsidian LAB_SCENARIO=newUser
  xcrun simctl ui "$U" content_size accessibility-large >/dev/null 2>&1
  shoot "$U" "small-obsidian-AXL-1-top" LAB_THEME=obsidian
  shoot "$U" "small-obsidian-AXL-3-graph" LAB_THEME=obsidian LAB_SCROLL=trends LAB_SELECT=6
  shoot "$U" "small-obsidian-AXL-4-coach" LAB_THEME=obsidian LAB_SCREEN=coach
  full "$U" "full-small-obsidian-AXL" LAB_THEME=obsidian
  xcrun simctl shutdown "$U" >/dev/null 2>&1
fi
rm -f "$OUT/shots/warmup.png" "$OUT/shots/warmup-small.png"
note "RESULT screenshots: $(ls "$OUT/shots" | wc -l | tr -d ' ') screen files, $(ls "$OUT/full" | wc -l | tr -d ' ') full-length files"
exit 0
