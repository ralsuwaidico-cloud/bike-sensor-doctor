#!/usr/bin/env bash
# Builds, tests, signs and (optionally) uploads the BikeComputer iPhone + Watch apps on a GitHub macOS runner.
#
# Inputs (environment, set by .github/workflows/ios.yml):
#   BUILD_NUMBER      CFBundleVersion for both apps (GitHub run number)
#   APPLE_TEAM_ID     secret  (optional until signing is set up)
#   ASC_KEY_ID        secret  App Store Connect API key ID
#   ASC_ISSUER_ID     secret  App Store Connect issuer ID
#   ASC_PRIVATE_KEY   secret  contents of the AuthKey_XXXX.p8 file
#   APP_READY         "true" when the App Store Connect app record exists (from ci/asc.py)
#   UPLOAD            "true" to upload to TestFlight (internal testers only)
#   SUPABASE_URL, SUPABASE_ANON_KEY, GOOGLE_WEB_CLIENT_ID, GOOGLE_IOS_CLIENT_ID
#                     optional account-service values, written into Info.plist at build time. Cyclift 1.0 ignores
#                     them: ReleaseFlags.accountsEnabled = false keeps accounts off even when they are set.
#   (The public support address is a static Info.plist value in project.yml since 1.0 — no secret.)
#
# Secrets only ever go to a 0600 file in $RUNNER_TEMP that is deleted at the end, and every log line that leaves the
# runner is passed through `scrub` (the repository and its logs are public).
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
OUT="$ROOT/build"
LOGS="$OUT/logs"
mkdir -p "$LOGS"
SUMMARY="$LOGS/summary.txt"
: > "$SUMMARY"
KEYDIR="${RUNNER_TEMP:-/tmp}/asc-key"
STATUS=0

note() { echo "$*" | tee -a "$SUMMARY"; }
scrub() {
  local s
  s=$(cat)
  for v in "${APPLE_TEAM_ID:-}" "${ASC_KEY_ID:-}" "${ASC_ISSUER_ID:-}" "${SUPABASE_ANON_KEY:-}" "${SUPABASE_URL:-}" "${GOOGLE_WEB_CLIENT_ID:-}" "${GOOGLE_IOS_CLIENT_ID:-}"; do
    [ -n "$v" ] && s=${s//"$v"/"<hidden>"}
  done
  printf '%s\n' "$s"
}
cleanup() { rm -rf "$KEYDIR" "$HOME/.appstoreconnect/private_keys"; }
trap cleanup EXIT

# Keep the part of an xcodebuild log that explains a failure: errors, warnings, test results, and the last lines.
digest() {
  local log=$1 name=$2
  {
    echo "=== $name: errors / failures ==="
    # Run 204: the unit job's one assertion message was cut off by the 400-line cap because 659 "Test Case … passed" lines
    # came first. Assertion / compiler errors and failing test names are listed first, uncapped by the passed lines.
    grep -E "error:|Failing tests|Test Case .* failed|\*\* .* FAILED \*\*" "$log" | grep -v "healthkit entitlement\|WCErrorCodeDeviceNotPaired" | head -200
    echo "=== $name: full filter ==="
    grep -E "error:|ERROR|FAILED|failed|Failing tests|Test Case .* (passed|failed)|Executed [0-9]+ test|\*\* .* (SUCCEEDED|FAILED) \*\*|Provisioning|provisioning|Signing|signing|No profiles|certificate" "$log" | head -400
    echo "=== $name: last 150 lines ==="
    tail -150 "$log"
  } | scrub > "$LOGS/$name.txt"
}

# STAGE selects what this invocation does (CI speed-up, 1 Nov 2026; ios/CI_PIPELINE.md). Each GitHub job runs one stage
# on its own macOS runner, so independent stages run in parallel; release runs only after every test stage passed.
#   all      everything in one job, one after another (the pre-1-Nov pipeline; kept as a fallback)
#   quick    compile + unit tests + layout checks of the main screens on iPhone SE at AX3 and a standard iPhone at L.
#            Never archives or uploads. NOT release evidence.
#   unit     Debug build-for-testing once, then the unit tests (BikeComputerTests)
#   smoke    Release build-for-testing once, then the launch / smoke UI tests (BikeComputerUITests)
#   layout   Release build-for-testing once, then the LayoutAudit on LAYOUT_DEVICES (one device per job in CI)
#   watch    Apple Watch screenshots (soft: never fails)
#   release  archive, App Store signing, verification and (when requested and every test job passed) the upload
# SCOPE (older input) still works: SCOPE=ui → STAGE=layout on LAYOUT_DEVICES.
SCOPE="${SCOPE:-full}"
STAGE="${STAGE:-}"
if [ -z "$STAGE" ]; then if [ "$SCOPE" = ui ]; then STAGE=layout; else STAGE=all; fi; fi
case "$STAGE" in all|quick|unit|smoke|smoke2|journeys|layout|watch|release) ;; *) echo "unknown STAGE $STAGE"; exit 2;; esac
LAYOUT_DEVICES="${LAYOUT_DEVICES:-small,standard,promax,owner}"
T0=$SECONDS; since() { echo "$(( (SECONDS - $1) / 60 ))m$(( (SECONDS - $1) % 60 ))s"; }
note "BikeComputer iOS CI — build ${BUILD_NUMBER:-?} — $(date -u '+%Y-%m-%d %H:%M UTC')"
note "Stage: $STAGE$([ "$STAGE" = layout ] && echo " (layout devices: $LAYOUT_DEVICES)")"
[ "$STAGE" = quick ] && note "QUICK CHECK — not release evidence (no full layout audit, no archive, never uploads)"
note "$(sw_vers -productName) $(sw_vers -productVersion), $(xcodebuild -version | tr '\n' ' ')"

# Swift packages are cloned into build/spm, which the workflow caches (keyed on project.yml). No signing material is
# ever written there.
SPM=(-clonedSourcePackagesDirPath "$OUT/spm")

# ---------------------------------------------------------------- project generation
TG=$SECONDS
if ! command -v xcodegen >/dev/null; then brew install xcodegen >/dev/null 2>&1; fi
note "XcodeGen $(xcodegen --version 2>/dev/null)"
if ! xcodegen generate --spec project.yml > "$LOGS/xcodegen.txt" 2>&1; then
  note "RESULT generate: FAILED"; cat "$LOGS/xcodegen.txt" | scrub >> "$SUMMARY"; exit 1
fi
note "RESULT generate: ok · $(since $TG)"

if [ "$STAGE" = watch ]; then
  TW=$SECONDS
  LAYOUT="$OUT/layout"; mkdir -p "$LAYOUT"
  bash ci/watch-shots.sh "$LAYOUT" || true
  for f in "$LAYOUT"/*.png; do [ -f "$f" ] && sips -Z 1100 "$f" >/dev/null 2>&1; done
  note "  watch screenshots: $(ls "$LAYOUT"/watch-*.png 2>/dev/null | wc -l | tr -d ' ') — $(tr '\n' ' ' < "$LOGS/watch-shots.txt" 2>/dev/null | head -c 400) · $(since $TW)"
  note "Total: $(since $T0)"
  exit 0
fi

# ---------------------------------------------------------------- simulators
SIM=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
best=None
for rt,devs in d.items():
    if ".iOS-" not in rt: continue
    ver=tuple(int(x) for x in rt.split(".iOS-")[1].split("-"))
    for x in devs:
        if x["name"].startswith("iPhone") and (best is None or ver>best[0]): best=(ver,x["udid"],x["name"])
print(best[1] if best else "")')
[ "$STAGE" = release ] || note "Test simulator: ${SIM:-none found}"

# build-for-testing once per configuration, then test-without-building against the .xctestrun it writes (the same
# binaries are used for every test in this job — they are not rebuilt per simulator).
# $1 = Debug | Release, rest = extra build settings. Prints the .xctestrun path (empty on failure).
bft() {
  local cfg=$1; shift
  local dd="$OUT/dd-$cfg" tb=$SECONDS
  xcodebuild build-for-testing -project BikeComputer.xcodeproj -scheme BikeComputer -configuration "$cfg" \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$dd" "${SPM[@]}" \
    CODE_SIGNING_ALLOWED=NO "$@" > "$OUT/build-$cfg.log" 2>&1
  local r=$?
  digest "$OUT/build-$cfg.log" "build-$cfg"
  if [ $r -ne 0 ]; then note "RESULT build ($cfg, for testing): FAILED (exit $r) · $(since $tb) — $(grep -E ' error: ' "$OUT/build-$cfg.log" | sed -E 's/.*error: //' | sort -u | head -3 | tr '\n' ' ' | cut -c1-400 | scrub)" >&2; return 1; fi
  note "RESULT build ($cfg, for testing): ok · $(since $tb)" >&2
  ls "$dd"/Build/Products/*.xctestrun 2>/dev/null | head -1
}
# $1 = xctestrun, $2 = simulator id, $3 = log file, rest = -only-testing / -skip-testing arguments
twb() {
  local xr=$1 id=$2 log=$3; shift 3
  xcodebuild test-without-building -xctestrun "$xr" -destination "id=$id" "$@" > "$log" 2>&1
}

# ---------------------------------------------------------------- V1 journey recording (owner 2 Nov: a screen recording,
# not screenshots): the simulator records h264 while JourneyTests drives onboarding → Home → Profile → Plan → relaunch
# for one persona. Published to ci-logs as ios/run-N/journey-<persona>.mp4 (downscaled with ffmpeg when the runner has it).
record_journey() {
  # run 148: macOS bash 3.2 expands every word of one `local` line before assigning any, so $persona was unbound here
  local persona="$1"; local LT=$SECONDS; local raw="$LAYOUT/journey-$persona-raw.mp4"; local out="$LAYOUT/journey-$persona.mp4"
  # run 151: the first journey started while the simulator was still booting (Apple logo for > 1 min in the recording,
  # the app's first screen came too late) — boot fully first, then record
  xcrun simctl bootstatus "$SIM" -b > /dev/null 2>&1 || true
  xcrun simctl io "$SIM" recordVideo --codec h264 --force "$raw" > "$OUT/record-$persona.log" 2>&1 &
  local rec=$!
  sleep 3
  TEST_RUNNER_BC_JOURNEY_PERSONA="$persona" TEST_RUNNER_LAYOUT_DIR="$LAYOUT" \
    twb "$RELEASE_XR" "$SIM" "$OUT/journey-$persona.log" -only-testing:BikeComputerUITests/JourneyTests
  local J=$?
  if [ $J -ne 0 ] && [ -n "$(launch_failed_tests "$OUT/journey-$persona.log")" ]; then
    kill -INT "$rec" 2>/dev/null; wait "$rec" 2>/dev/null; sleep 2
    xcrun simctl io "$SIM" recordVideo --codec h264 --force "$raw" > "$OUT/record-$persona-attempt2.log" 2>&1 &
    rec=$!; sleep 3
    TEST_RUNNER_BC_JOURNEY_PERSONA="$persona" TEST_RUNNER_LAYOUT_DIR="$LAYOUT" retry_launch_failures "$RELEASE_XR" "$SIM" "journey-$persona" "$OUT/journey-$persona.log"
    J=$?
  fi
  kill -INT "$rec" 2>/dev/null; wait "$rec" 2>/dev/null; sleep 2
  digest "$OUT/journey-$persona.log" "journey-$persona"
  if [ -f "$raw" ]; then
    if command -v ffmpeg >/dev/null 2>&1; then
      ffmpeg -y -loglevel error -i "$raw" -vf "scale=-2:960" -r 20 -c:v libx264 -preset veryfast -crf 30 -an "$out" && rm -f "$raw" || mv "$raw" "$out"
    else mv "$raw" "$out"; fi
    note "  journey $persona: $([ $J -eq 0 ] && echo ok || echo "FAILED (exit $J)") · recording $(( $(stat -f%z "$out") / 1024 )) KB · $(since $LT)"
  else note "  journey $persona: $([ $J -eq 0 ] && echo ok || echo "FAILED (exit $J)") · no recording produced · $(since $LT)"; fi
  [ $J -eq 0 ] || STATUS=1
  return $J
}

# Run 149: the three recorded journeys (≈11 min each) plus smoke exceeded the smoke job's limit — they run in a job of
# their own, in parallel with the others; all three stay release-blocking.
run_journeys() {
  TS=$SECONDS
  release_products || { note "RESULT journey (recorded): FAILED (build)"; STATUS=1; return; }
  mkdir -p "$LAYOUT"
  # a compressor for the recordings (run 149: none on the runner, so the 78 MB hybrid recording was not published)
  command -v ffmpeg >/dev/null 2>&1 || brew install --quiet ffmpeg >/dev/null 2>&1 || note "  ffmpeg unavailable — recordings published only if small enough"
  local U=0
  warm_release_app
  for persona in hybrid cycling strength; do record_journey "$persona" || U=1; done
  note "RESULT journey (recorded): $([ $U -eq 0 ] && echo ok || echo FAILED) — JourneyTests hybrid, cycling, strength · $(since $TS)"
  [ $U -eq 0 ] || STATUS=1
}

run_unit() {
  TS=$SECONDS
  local xr; xr=$(bft Debug) || { note "RESULT tests: FAILED (build)"; STATUS=1; return; }
  twb "$xr" "$SIM" "$OUT/test.log" -resultBundlePath "$OUT/tests.xcresult" -only-testing:BikeComputerTests
  T=$?
  digest "$OUT/test.log" test
  if [ $T -eq 0 ]; then note "RESULT tests: ok ($(grep -Eo 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$OUT/test.log" | tail -1)) · $(since $TS)"
  else note "RESULT tests: FAILED (exit $T) · $(since $TS) — $(grep -A3 'Failing tests:' "$OUT/test.log" | tail -3 | tr '\n' ' ' | cut -c1-300 | scrub)"; STATUS=1; fi
}

RELEASE_XR=""
release_products() {  # Release build for the UI tests (the shipped configuration), built once per job
  [ -n "$RELEASE_XR" ] && return 0
  RELEASE_XR=$(bft Release ENABLE_TESTABILITY=YES) && [ -n "$RELEASE_XR" ]
}

# ---------------------------------------------------------------- launch smoke tests, RELEASE build on the simulator
# The shipped app is a Release build: build 27 crashed at launch on devices updated from build 24 while every Debug
# unit test passed. These tests launch the Release app fresh and with a build-24-shaped store and open all five tabs.
# Any crash fails the run before archiving, and the simulator's crash report is kept with the logs.
# Runs 194–197 (8 Nov): the FIRST XCUITest launch of the cold Release app in a job, right after the simulator booted,
# timed out or was far slower than usual (smoke in 194–196, the hybrid journey in 197) while every later launch was
# fine. Boot fully (as the journeys do since run 151), then install + launch + terminate the app once so the first
# test's launch is warm. $1 = simulator id (default $SIM).
warm_release_app() {
  local sim=${1:-$SIM}
  xcrun simctl bootstatus "$sim" -b > /dev/null 2>&1 || true
  local app; app=$(find "$(dirname "$RELEASE_XR")" -maxdepth 3 -name 'BikeComputer.app' -path '*Release-iphonesimulator*' 2>/dev/null | head -1)
  [ -n "$app" ] || return 0
  xcrun simctl install "$sim" "$app" > /dev/null 2>&1 || true
  xcrun simctl launch "$sim" com.ralsuwaidico.bikecomputer > /dev/null 2>&1 || true
  sleep 10
  xcrun simctl terminate "$sim" com.ralsuwaidico.bikecomputer > /dev/null 2>&1 || true
}

# Owner-approved (8 Nov 14:32) narrowly scoped retry for LAUNCH-INFRASTRUCTURE failures only — the same rule the layout
# audit has used since run 71. $1 = log of the attempt, prints the test ids whose ONLY failure was that XCTest could not
# launch the app (or lost it right after); prints nothing when any failure is a real check, so nothing else is retried.
launch_failed_tests() {
  local log=$1
  # every failing test …
  local failed; failed=$(grep -Eo "Test Case '-\[[A-Za-z0-9_.]+ [A-Za-z0-9_]+\]' failed" "$log" | sed -E "s/Test Case '-\[([^ ]+) ([^]]+)\]' failed/\1\/\2/" | sort -u)
  [ -n "$failed" ] || return 0
  # … must have failed on launch infrastructure and nothing else
  local t; for t in $failed; do
    local cls=${t%%/*}; cls=${cls##*.}; local m=${t##*/}
    local errs; errs=$(grep -E "error: -\[[A-Za-z0-9_.]*${cls} ${m}\]" "$log")
    [ -n "$errs" ] || return 0
    if echo "$errs" | grep -vq "Timed out while launching application\|Timed out while requesting launch progress\|Failed to get background assertion for target app with pid 0\|Simulator device failed to launch\|Timed out while loading Accessibility\|failed to initialize for UI testing"; then return 0; fi
  done
  echo "$failed"
}
# $1 xctestrun · $2 sim · $3 label · $4 first-attempt log · rest = original -only/-skip arguments. Re-runs ONLY the tests that
# failed on launch infrastructure, once, after a simulator reboot; both attempts are kept and summarised.
retry_launch_failures() {
  local xr=$1 sim=$2 label=$3 log=$4; shift 4
  local tests; tests=$(launch_failed_tests "$log")
  [ -n "$tests" ] || return 1
  note "  $label: launch-infrastructure failure only ($(echo $tests | tr ' ' ',')) — attempt 1 kept as $label-launchfail; rebooting the simulator and retrying those tests once"
  cp "$log" "${log%.log}-launchfail.log"; digest "${log%.log}-launchfail.log" "$label-launchfail"
  xcrun simctl shutdown "$sim" >/dev/null 2>&1; xcrun simctl boot "$sim" >/dev/null 2>&1; sleep 20
  warm_release_app "$sim"
  local only=(); local t; for t in $tests; do only+=("-only-testing:BikeComputerUITests/${t#*.}"); done
  twb "$xr" "$sim" "${log%.log}-attempt2.log" "${only[@]}"
  local r=$?
  digest "${log%.log}-attempt2.log" "$label-attempt2"
  note "  $label: attempt 2 ($(echo $tests | tr ' ' ',')): $([ $r -eq 0 ] && echo passed || echo FAILED) — both attempts are in the logs"
  return $r
}

# Run 207: the smoke job passed its 65-minute step limit once the hub reliability loops (60 open/close cycles at a human
# pace) and the four new end-to-end journeys joined it, and was cancelled with no result. Those classes run in their own
# matrix job ("flows", stage smoke2); the smoke job keeps the launch, layout-state and screen smokes.
FLOW_CLASSES="HubTapReliabilityTests StrengthSessionJourneyTests PlanEditPreviewApplyTests PlanProgressRecoveryScreensTests DeleteAllDataJourneyTests"
run_smoke() {
  TS=$SECONDS
  release_products || { note "RESULT launch smoke (Release): FAILED (build)"; STATUS=1; return; }
  warm_release_app
  local SKIP=(-skip-testing:BikeComputerUITests/JourneyTests); for c in $FLOW_CLASSES; do SKIP+=(-skip-testing:BikeComputerUITests/$c); done
  twb "$RELEASE_XR" "$SIM" "$OUT/uitest.log" -resultBundlePath "$OUT/uitests.xcresult" -only-testing:BikeComputerUITests "${SKIP[@]}"
  U=$?
  digest "$OUT/uitest.log" launch-smoke
  if [ $U -ne 0 ]; then retry_launch_failures "$RELEASE_XR" "$SIM" launch-smoke "$OUT/uitest.log"; local R=$?; [ $R -eq 0 ] && U=0; fi
  if [ $U -eq 0 ]; then note "RESULT launch smoke (Release): ok ($(grep -Eo 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$OUT/uitest.log" | tail -1)) · $(since $TS)"
  else
    note "RESULT launch smoke (Release): FAILED (exit $U) · $(since $TS)"; STATUS=1
    # crash reports of the app from the simulator run, scrubbed, as text
    find "$HOME/Library/Logs/DiagnosticReports" -name 'BikeComputer*' -mmin -120 2>/dev/null | head -5 | while read -r f; do
      { echo "=== $(basename "$f") ==="; head -c 60000 "$f"; } | scrub >> "$LOGS/crash-reports.txt"
    done
    xcrun simctl spawn "$SIM" log show --last 15m --predicate 'process == "BikeComputer" OR (eventMessage CONTAINS "BikeComputer" AND messageType == error)' 2>/dev/null \
      | grep -v "^Filtering" | tail -400 | scrub > "$LOGS/sim-app-log.txt"
    export_fail_shots "$OUT/uitests.xcresult" smoke
  fi
}

run_smoke2() {   # "flows": hub reliability + the end-to-end UI journeys (strength live session, plan edit, screens, delete all)
  TS=$SECONDS
  release_products || { note "RESULT flows (Release): FAILED (build)"; STATUS=1; return; }
  warm_release_app
  local ONLY=(); for c in $FLOW_CLASSES; do ONLY+=(-only-testing:BikeComputerUITests/$c); done
  twb "$RELEASE_XR" "$SIM" "$OUT/flows.log" -resultBundlePath "$OUT/flows.xcresult" "${ONLY[@]}"
  U=$?
  digest "$OUT/flows.log" flows
  if [ $U -eq 0 ]; then note "RESULT flows (hub reliability + UI journeys): ok · $(since $TS)"; else
    note "RESULT flows: FAILED (exit $U) · $(since $TS) — $(grep -E 'error:' "$OUT/flows.log" | grep -v 'healthkit\|WCError' | head -8 | sed 's/.*UITests\///' | cut -c1-400 | tr '\n' ' ')"; STATUS=1
    export_fail_shots "$OUT/flows.xcresult" flows
  fi
}

# Run 205: the failure screenshots the UI tests attach (XCTAttachment named FAIL-…) stayed inside the xcresult, which the
# owner's environment cannot download. Export them into $OUT/layout so the publish job copies them to ci-logs/…/layout.
export_fail_shots() {   # <xcresult> <stage>
  local xr="$1" tag="$2" d; [ -d "$xr" ] || return 0
  d=$(mktemp -d)
  xcrun xcresulttool export attachments --path "$xr" --output-path "$d" >/dev/null 2>&1 || return 0
  mkdir -p "$OUT/layout"
  python3 - "$d" "$OUT/layout" "$tag" <<'PY' 2>/dev/null || true
import json, os, shutil, sys
src, dst, tag = sys.argv[1:4]
m = os.path.join(src, "manifest.json")
if not os.path.exists(m): sys.exit(0)
n = 0
for t in json.load(open(m)):
    for a in t.get("attachments", []):
        name = a.get("suggestedHumanReadableName") or a.get("exportedFileName") or ""
        if not name.startswith("FAIL-") or n >= 40: continue
        f = os.path.join(src, a["exportedFileName"])
        if os.path.exists(f):
            shutil.copy(f, os.path.join(dst, f"{tag}-{name}".replace("/", "-") + ("" if name.endswith(".png") else ".png"))); n += 1
print(f"exported {n} FAIL screenshots")
PY
}

# ---------------------------------------------------------------- layout audit (quality release)
# The LayoutAudit UI test (skipped unless LAYOUT_DIR is set) on a small iPhone, a standard iPhone and a Pro Max at
# several text sizes: PNG screenshots of the key screens (published, downscaled, to the ci-logs branch) and frame checks
# of the key controls (inside the window, no overlap, >= 44 pt, hittable). Demo data only ("Demo" rider).
LAYOUT="$OUT/layout"; mkdir -p "$LAYOUT"
simpick() {  # $1 = exact name preferred, $2 = substring fallback
  xcrun simctl list devices available -j | python3 -c '
import json,sys
exact,sub=sys.argv[1:3]
d=json.load(sys.stdin)["devices"]; best=None
for rt,devs in d.items():
    if ".iOS-" not in rt: continue
    ver=tuple(int(x) for x in rt.split(".iOS-")[1].split("-"))
    for x in devs:
        n=x["name"]
        if n!=exact and sub not in n: continue
        rank=(ver, n==exact)
        if best is None or rank>best[0]: best=(rank,x["udid"],n)
print((best[1]+"|"+best[2]) if best else "")' "$1" "$2"; }
layout_sims() {  # creates/picks only the simulators this job needs (LAYOUT_DEVICES)
  RT=$(xcrun simctl list runtimes -j | python3 -c '
import json,sys
r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and ".iOS-" in x["identifier"]]
r.sort(key=lambda x: [int(p) for p in x["version"].split(".")])
print(r[-1]["identifier"] if r else "")')
  SMALL=""; STD=""; MAX=""; OWNER=""
  if [[ ",$LAYOUT_DEVICES," == *",small,"* ]]; then
    for T in iPhone-SE-3rd-generation iPhone-SE-2nd-generation iPhone-13-mini iPhone-12-mini; do
      U=$(xcrun simctl create "Audit small" "com.apple.CoreSimulator.SimDeviceType.$T" "$RT" 2>/dev/null) && { SMALL="$U|$T"; break; }
    done
    [ -n "$SMALL" ] || SMALL=$(simpick "iPhone 16e" "16e")
  fi
  STD=$(simpick "iPhone 17" "iPhone 16"); [ -n "$STD" ] || STD="$SIM|default"
  [[ ",$LAYOUT_DEVICES," == *",promax,"* ]] && MAX=$(simpick "iPhone 17 Pro Max" "Pro Max")
  # RC2: the owner's screen (393 × 852 pt: iPhone 16 / 15 / 14 Pro). Created on the newest runtime when the device type
  # exists there, else an existing iPhone 16 / 15, else the standard device (said so in the summary).
  if [[ ",$LAYOUT_DEVICES," == *",owner,"* ]]; then
    for T in iPhone-16 iPhone-15 iPhone-15-Pro iPhone-14-Pro; do
      U=$(xcrun simctl create "Audit owner" "com.apple.CoreSimulator.SimDeviceType.$T" "$RT" 2>/dev/null) && { OWNER="$U|$T"; break; }
    done
    [ -n "$OWNER" ] || OWNER=$(simpick "iPhone 16" "iPhone 15")
    [ -n "$OWNER" ] || OWNER="${STD%%|*}|${STD#*|} (no 393-pt device on this runtime)"
  fi
  note "Layout audit simulators: small=${SMALL#*|} standard=${STD#*|} max=${MAX#*|} owner=${OWNER#*|} (runtime ${RT##*.})"
}
LAYOUT_OK=1
# $1 = name, $2 = simulator id, $3 = sizes, $4 = tests (space separated, e.g. "LayoutAudit" or "LayoutAudit/testHomeStates")
layout_one() {
  local LNAME=$1 LID=$2 LSIZES=$3 TESTS=$4 LT=$SECONDS L a
  [ -n "${LAYOUT_SIZES_OVERRIDE:-}" ] && LSIZES="$LAYOUT_SIZES_OVERRIDE"   # e.g. L,AX3 for the onboarding screenshots
  [ -n "$LID" ] || { note "  layout $LNAME: no simulator"; return; }
  local ONLY=(); for a in $TESTS; do ONLY+=("-only-testing:BikeComputerUITests/$a"); done
  local LEXTRAS=0; { [ "$LNAME" = "standard" ] || [ "$LNAME" = "owner" ]; } && LEXTRAS=1
  [ "$STAGE" = quick ] && LEXTRAS=0
  TEST_RUNNER_LAYOUT_DIR="$LAYOUT" TEST_RUNNER_LAYOUT_DEVICE="$LNAME" TEST_RUNNER_LAYOUT_SIZES="$LSIZES" TEST_RUNNER_LAYOUT_EXTRAS="$LEXTRAS" \
    rm -rf "$OUT/layout-$LNAME.xcresult"; twb "$RELEASE_XR" "$LID" "$OUT/layout-$LNAME.log" -resultBundlePath "$OUT/layout-$LNAME.xcresult" "${ONLY[@]}"
  L=$?
  # one retry ONLY when the simulator failed to launch the app (infrastructure, run 71) — never for a failed check
  if [ $L -ne 0 ] && grep -q "Timed out while launching application\|Simulator device failed to launch\|Timed out while loading Accessibility\|failed to initialize for UI testing" "$OUT/layout-$LNAME.log"; then
    note "  layout $LNAME: simulator could not launch the app — rebooting it and retrying once"
    mv "$OUT/layout-$LNAME.log" "$OUT/layout-$LNAME-launchfail.log"
    xcrun simctl shutdown "$LID" >/dev/null 2>&1; xcrun simctl boot "$LID" >/dev/null 2>&1; sleep 20
    TEST_RUNNER_LAYOUT_DIR="$LAYOUT" TEST_RUNNER_LAYOUT_DEVICE="$LNAME" TEST_RUNNER_LAYOUT_SIZES="$LSIZES" TEST_RUNNER_LAYOUT_EXTRAS="$LEXTRAS" \
      rm -rf "$OUT/layout-$LNAME.xcresult"; twb "$RELEASE_XR" "$LID" "$OUT/layout-$LNAME.log" -resultBundlePath "$OUT/layout-$LNAME.xcresult" "${ONLY[@]}"
    L=$?
  fi
  digest "$OUT/layout-$LNAME.log" "layout-$LNAME"
  [ $L -ne 0 ] && export_fail_shots "$OUT/layout-$LNAME.xcresult" "layout-$LNAME"
  if [ $L -eq 0 ]; then note "  layout $LNAME ($LSIZES): ok · $(since $LT)"; else note "  layout $LNAME ($LSIZES): FAILED (exit $L) · $(since $LT) — $(grep -E ' error: ' "$OUT/layout-$LNAME.log" | sed -E 's/.*error: //' | sort -u | head -3 | tr '\n' ' ' | cut -c1-400 | scrub)"; LAYOUT_OK=0; fi
}
layout_finish() {
  N_PNG=$(ls "$LAYOUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
  for f in "$LAYOUT"/*.png; do [ -f "$f" ] && sips -Z 1100 "$f" >/dev/null 2>&1; done
  cp "$LAYOUT"/*.txt "$LOGS/" 2>/dev/null || true
  if [ $LAYOUT_OK -eq 1 ]; then note "RESULT layout audit: ok ($N_PNG screenshots)"; else note "RESULT layout audit: FAILED ($N_PNG screenshots)"; STATUS=1; fi
}
run_layout() {  # the full layout audit on LAYOUT_DEVICES
  layout_sims
  release_products || { note "RESULT layout audit: FAILED (build)"; STATUS=1; return; }
  local spec LNAME LID LSIZES
  for spec in "small|${SMALL%%|*}|L,AX3" "standard|${STD%%|*}|L,XXXL" "promax|${MAX%%|*}|L" "owner|${OWNER%%|*}|L,XXXL"; do
    IFS='|' read -r LNAME LID LSIZES <<< "$spec"
    case ",$LAYOUT_DEVICES," in *",$LNAME,"*) ;; *) continue;; esac
    layout_one "$LNAME" "$LID" "$LSIZES" "${LAYOUT_TEST:-LayoutAudit DesignSystemAudit}"   # DesignSystemAudit: the component gallery, light + dark (ios/DESIGN_SYSTEM.md)
  done
  layout_finish
}

# ---------------------------------------------------------------- quick-before-full (ios/CI_PROCESS.md)
# The ci-logs branch keeps two markers written by the workflow's publish job: ios/ci/last-green.txt (the commit of the last
# full run that passed every test job and the release job) and ios/ci/quick-green/<tree-hash> (one file per source tree
# that passed a quick run). Keyed on the TREE hash, so a commit that only changes the message (e.g. adding [testflight])
# still counts as checked, while any source change needs its own quick run.
CILOGS=""
cilogs() {   # checks out ci-logs (shallow) once; prints its path or nothing
  [ -n "$CILOGS" ] && { echo "$CILOGS"; return; }
  local d; d=$(mktemp -d)
  if git -C "$ROOT" remote get-url origin >/dev/null 2>&1 && git clone -q --depth 1 --branch ci-logs "$(git -C "$ROOT" remote get-url origin)" "$d" 2>/dev/null; then CILOGS="$d"; echo "$d"; fi
}
quick_targets() {   # QUICK_UI for the files changed since the last green full run; the default set when that is unknown
  local base="" d; d=$(cilogs)
  [ -n "$d" ] && [ -f "$d/ios/ci/last-green.txt" ] && base=$(tr -d '[:space:]' < "$d/ios/ci/last-green.txt")
  if [ -n "$base" ] && { git -C "$ROOT" cat-file -e "$base" 2>/dev/null || git -C "$ROOT" fetch -q --depth 1 origin "$base" 2>/dev/null; }; then
    git -C "$ROOT" diff --name-only "$base" HEAD | python3 "$ROOT/../tools/ci-targets.py" --quick-ui
    note "  targets from the files changed since the last green full run ${base:0:7}" >&2
  else
    python3 "$ROOT/../tools/ci-targets.py" --quick-ui </dev/null
    note "  no last-green commit known — default quick set" >&2
  fi
}
quick_green_for_head() {   # 0 when a quick run passed for HEAD's source tree
  local d t; d=$(cilogs); t=$(git -C "$ROOT" rev-parse 'HEAD^{tree}')
  [ -n "$d" ] && [ -f "$d/ios/ci/quick-green/$t" ]
}

case "$STAGE" in
  unit)  run_unit ;;
  smoke) run_smoke ;;
  smoke2) run_smoke2 ;;
  journeys) run_journeys ;;
  layout) run_layout ;;
  quick)
    run_unit
    # QUICK_UI: the UI tests for the screens being changed. Given explicitly (workflow input) it is used as is; otherwise
    # it is computed by tools/ci-targets.py from the files changed since the last green full run (ios/CI_PROCESS.md).
    # Run 126: adding the owner-screens audit and the upgrade smoke to every quick run made it 51 min — targets only.
    # "[ci ui: A/b C/d]" in the head commit message adds those UI tests to the quick set (a push cannot pass workflow inputs)
    EXTRA_UI=$(git -C "$ROOT" log -1 --format=%B | sed -n 's/.*\[ci ui: *\([^]]*\)\].*/\1/p' | head -1)
    if [ -z "${QUICK_UI:-}" ]; then QUICK_UI=$(quick_targets); fi
    [ -n "$EXTRA_UI" ] && QUICK_UI="$QUICK_UI $EXTRA_UI"
    note "Quick UI targets: $QUICK_UI"
    LAYOUT_DEVICES="small,standard"; layout_sims
    if release_products; then
      layout_one small "${SMALL%%|*}" AX3 "$QUICK_UI"
      layout_one standard "${STD%%|*}" L "$QUICK_UI"
      # V1: the hybrid journey, recorded, on the test simulator (owner: a screen recording of onboarding → Home)
      record_journey hybrid || true
      layout_finish
    else note "RESULT layout audit: FAILED (build)"; STATUS=1; fi
    note "RESULT archive: skipped (quick check)"; note "RESULT upload: skipped (quick check never uploads)"
    note "Total: $(since $T0)"; exit $STATUS ;;
  all)
    run_unit; run_smoke; run_smoke2; run_journeys; run_layout
    bash ci/watch-shots.sh "$LAYOUT" || true
    note "  watch screenshots: $(ls "$LAYOUT"/watch-*.png 2>/dev/null | wc -l | tr -d ' ') — $(tr '\n' ' ' < "$LOGS/watch-shots.txt" 2>/dev/null | head -c 400)"
    for f in "$LAYOUT"/watch-*.png; do [ -f "$f" ] && sips -Z 1100 "$f" >/dev/null 2>&1; done ;;
esac
if [ "$STAGE" != all ] && [ "$STAGE" != release ]; then note "Total: $(since $T0)"; exit $STATUS; fi
if [ "$SCOPE" = ui ]; then
  note "RESULT archive: skipped (scope ui)"; note "RESULT upload: skipped (scope ui never uploads)"
  note "Total: $(since $T0)"
  exit $STATUS
fi
# release stage in CI: the workflow starts it only when every test job succeeded and passes TESTS_OK=success; the
# upload below refuses anything else (belt and braces: the gate is the same as before, only split across jobs).
if [ "$STAGE" = release ] && [ "${TESTS_OK:-}" != "success" ]; then STATUS=1; note "Test jobs: ${TESTS_OK:-unknown} — this build will not be uploaded"; fi
# quick-before-full: a full run is only accepted for a source tree that already passed a quick run, or with
# "[full-override: <reason>]" in the commit message (the reason is printed). Never weakens the test gates above.
if [ "$STAGE" = release ] || [ "$STAGE" = all ]; then
  if quick_green_for_head; then note "Quick check: passed for this source tree"
  elif reason=$(printf '%s' "${HEAD_MSG:-}" | grep -oE '\[full-override:[^]]*\]'); then note "Quick check: none for this tree — override accepted $reason"
  else
    note "RESULT archive: refused — no green quick run for this source tree (push with [ci quick] first, or add [full-override: <reason>] to the commit message)"
    note "Total: $(since $T0)"; exit 1
  fi
fi
TA=$SECONDS

# ---------------------------------------------------------------- archive (device build)
# The archive is ad-hoc signed ("-"): no certificate, no registered device. The entitlements (HealthKit) are embedded
# so the App Store export can re-sign with Apple's cloud-managed distribution certificate.
TEAM_ARGS=()
[ -n "${APPLE_TEAM_ID:-}" ] && TEAM_ARGS=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID")
# account-service configuration → Info.plist (values stay out of the logs; only presence is reported)
CLOUD_ARGS=(SUPABASE_URL="${SUPABASE_URL:-}" SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" GOOGLE_WEB_CLIENT_ID="${GOOGLE_WEB_CLIENT_ID:-}" GOOGLE_IOS_CLIENT_ID="${GOOGLE_IOS_CLIENT_ID:-}")
if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_ANON_KEY:-}" ]; then note "Accounts: values present but switched off in 1.0 (ReleaseFlags.accountsEnabled = false)"
else note "Accounts: off (no values; ReleaseFlags.accountsEnabled = false in 1.0)"; fi
ARCHIVE="$OUT/BikeComputer.xcarchive"
archive() {
  local mode=$1; shift
  rm -rf "$ARCHIVE"
  xcodebuild archive -project BikeComputer.xcodeproj -scheme BikeComputer -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" "${SPM[@]}" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" "${CLOUD_ARGS[@]}" ${TEAM_ARGS[@]+"${TEAM_ARGS[@]}"} "$@" > "$OUT/archive-$mode.log" 2>&1
  local r=$?
  digest "$OUT/archive-$mode.log" "archive-$mode"
  return $r
}
ARCH_MODE=""
if archive adhoc CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- PROVISIONING_PROFILE_SPECIFIER= \
     CODE_SIGNING_REQUIRED=NO AD_HOC_CODE_SIGNING_ALLOWED=YES; then
  ARCH_MODE=adhoc
elif archive unsigned CODE_SIGNING_ALLOWED=NO; then
  ARCH_MODE=unsigned
fi
if [ -z "$ARCH_MODE" ]; then note "RESULT archive: FAILED"; exit 1; fi
note "RESULT archive: ok ($ARCH_MODE) · $(since $TA)"
for app in "$ARCHIVE/Products/Applications/BikeComputer.app" "$ARCHIVE/Products/Applications/BikeComputer.app/Watch/BikeComputerWatch.app"; do
  if [ -d "$app" ]; then
    DN=$(/usr/libexec/PlistBuddy -c 'Print CFBundleDisplayName' "$app/Info.plist" 2>/dev/null)
    note "  contains $(basename "$app") $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Info.plist")) — display name '$DN'"
    [ "$DN" = "Cyclift" ] || { note "    display name is not Cyclift"; STATUS=1; }
    # App Store privacy manifest must be inside each app bundle and be a valid plist with tracking off
    if [ -f "$app/PrivacyInfo.xcprivacy" ] && plutil -lint -s "$app/PrivacyInfo.xcprivacy" \
       && [ "$(/usr/libexec/PlistBuddy -c 'Print NSPrivacyTracking' "$app/PrivacyInfo.xcprivacy" 2>/dev/null)" = "false" ]; then
      note "    privacy manifest: present, tracking false"
    else note "    privacy manifest: MISSING or invalid"; STATUS=1; fi
    if /usr/libexec/PlistBuddy -c 'Print NSLocationAlwaysAndWhenInUseUsageDescription' "$app/Info.plist" >/dev/null 2>&1; then
      note "    Info.plist still asks for Always location (not used in 1.0)"; STATUS=1; fi
  else note "  MISSING $app"; STATUS=1; fi
  if [ -d "$app" ]; then
    if codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q "com.apple.developer.healthkit"; then
      note "    HealthKit entitlement embedded in archive: yes"
    else note "    HealthKit entitlement embedded in archive: no"; fi
  fi
done

# ---------------------------------------------------------------- export (App Store signing in Apple's cloud)
if [ -z "${ASC_PRIVATE_KEY:-}" ] || [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
  note "RESULT sign: skipped (App Store Connect secrets not set yet)"
  exit $STATUS
fi
mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR"
KEY="$KEYDIR/AuthKey_${ASC_KEY_ID}.p8"
( umask 077; printf '%s\n' "$ASC_PRIVATE_KEY" | sed 's/\\n/\n/g' > "$KEY" )
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>${APPLE_TEAM_ID}</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" "${AUTH[@]}" > "$OUT/export.log" 2>&1
E=$?
digest "$OUT/export.log" export
if [ $E -ne 0 ]; then note "RESULT sign: FAILED (exit $E)"; exit 1; fi
IPA=$(ls "$OUT"/export/*.ipa 2>/dev/null | head -1)
[ -f "$IPA" ] || { note "RESULT sign: FAILED (no .ipa produced)"; exit 1; }
note "RESULT sign: ok ($(basename "$IPA"), $(stat -f%z "$IPA") bytes)"

# ---------------------------------------------------------------- verify the signed apps before uploading
rm -rf "$OUT/ipa"; mkdir -p "$OUT/ipa"; (cd "$OUT/ipa" && unzip -q "$IPA")
VERIFY_OK=1
check_app() {
  local app=$1 bundle=$2 ent
  if ! codesign --verify --strict "$app" 2>>"$LOGS/verify.txt"; then note "  $bundle: signature INVALID"; VERIFY_OK=0; return; fi
  ent=$(codesign -d --entitlements - --xml "$app" 2>/dev/null)
  printf '%s\n' "--- $bundle" "$ent" | scrub >> "$LOGS/verify.txt"
  local appid hk gta siwa
  read -r appid hk gta siwa < <(printf '%s' "$ent" | python3 -c '
import plistlib,sys
d=plistlib.loads(sys.stdin.buffer.read())
print(d.get("application-identifier",""), str(d.get("com.apple.developer.healthkit",False)).lower(), str(d.get("get-task-allow",False)).lower(), "yes" if d.get("com.apple.developer.applesignin") else "no")')
  local line="  $bundle: signature valid"
  [[ "$appid" == *".$bundle" ]] && line+=", app ID ok" || { line+=", app ID WRONG"; VERIFY_OK=0; }
  [ "$hk" = "true" ] && line+=", HealthKit ok" || { line+=", HealthKit MISSING"; VERIFY_OK=0; }
  [ "$gta" = "true" ] && { line+=", debug flag set (not App Store)"; VERIFY_OK=0; }
  if [ "$bundle" = "com.ralsuwaidico.bikecomputer" ]; then
    [ "$siwa" = "yes" ] && line+=", Sign in with Apple ok" || { line+=", Sign in with Apple MISSING"; VERIFY_OK=0; }
  fi
  note "$line"
}
check_app "$OUT/ipa/Payload/BikeComputer.app" com.ralsuwaidico.bikecomputer
check_app "$OUT/ipa/Payload/BikeComputer.app/Watch/BikeComputerWatch.app" com.ralsuwaidico.bikecomputer.watchkitapp
if [ $VERIFY_OK -ne 1 ]; then note "RESULT verify: FAILED"; exit 1; fi
note "RESULT verify: ok"

# ---------------------------------------------------------------- upload to TestFlight (internal testers only)
if [ "${APP_READY:-false}" != "true" ]; then note "RESULT upload: skipped (App Store Connect app record not created yet)"; exit $STATUS; fi
if [ "${UPLOAD:-false}" != "true" ]; then note "RESULT upload: skipped (not requested for this run)"; exit $STATUS; fi
if [ $STATUS -ne 0 ]; then note "RESULT upload: skipped (tests failed)"; exit $STATUS; fi
mkdir -p "$HOME/.appstoreconnect/private_keys"; chmod 700 "$HOME/.appstoreconnect/private_keys"
cp "$KEY" "$HOME/.appstoreconnect/private_keys/"
xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" > "$OUT/upload.log" 2>&1
U=$?
scrub < "$OUT/upload.log" | tail -60 > "$LOGS/upload.txt"
if [ $U -ne 0 ] || grep -qiE "ERROR ITMS|Failed to upload|UPLOAD FAILED" "$OUT/upload.log"; then note "RESULT upload: FAILED (exit $U)"; exit 1; fi
note "RESULT upload: ok — build ${BUILD_NUMBER} sent to App Store Connect; TestFlight processing takes about 5-30 minutes (the testflight job reports when it is ready)"
note "Total: $(since $T0)"
exit $STATUS
