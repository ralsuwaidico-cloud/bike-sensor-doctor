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
#                     optional account-service values, written into Info.plist at build time (empty = accounts off)
#   CYCLIFT_SUPPORT_EMAIL optional public support address for the in-app legal pages (empty = "see the support page")
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
    grep -E "error:|ERROR|FAILED|failed|Failing tests|Test Case .* (passed|failed)|Executed [0-9]+ test|\*\* .* (SUCCEEDED|FAILED) \*\*|Provisioning|provisioning|Signing|signing|No profiles|certificate" "$log" | head -400
    echo "=== $name: last 150 lines ==="
    tail -150 "$log"
  } | scrub > "$LOGS/$name.txt"
}

note "BikeComputer iOS CI — build ${BUILD_NUMBER:-?} — $(date -u '+%Y-%m-%d %H:%M UTC')"
note "$(sw_vers -productName) $(sw_vers -productVersion), $(xcodebuild -version | tr '\n' ' ')"

# ---------------------------------------------------------------- project generation
if ! command -v xcodegen >/dev/null; then brew install xcodegen >/dev/null 2>&1; fi
note "XcodeGen $(xcodegen --version 2>/dev/null)"
if ! xcodegen generate --spec project.yml > "$LOGS/xcodegen.txt" 2>&1; then
  note "RESULT generate: FAILED"; cat "$LOGS/xcodegen.txt" | scrub >> "$SUMMARY"; exit 1
fi
note "RESULT generate: ok"

# ---------------------------------------------------------------- unit tests on the iOS simulator
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
note "Test simulator: ${SIM:-none found}"
xcodebuild test -project BikeComputer.xcodeproj -scheme BikeComputer -configuration Debug \
  -destination "id=$SIM" -resultBundlePath "$OUT/tests.xcresult" -only-testing:BikeComputerTests \
  CODE_SIGNING_ALLOWED=NO > "$OUT/test.log" 2>&1
T=$?
digest "$OUT/test.log" test
if [ $T -eq 0 ]; then note "RESULT tests: ok ($(grep -Eo 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$OUT/test.log" | tail -1))"
else note "RESULT tests: FAILED (exit $T)"; STATUS=1; fi

# ---------------------------------------------------------------- launch smoke tests, RELEASE build on the simulator
# The shipped app is a Release build: build 27 crashed at launch on devices updated from build 24 while every Debug
# unit test passed. These tests launch the Release app fresh and with a build-24-shaped store and open all five tabs.
# Any crash fails the run before archiving, and the simulator's crash report is kept with the logs.
xcodebuild test -project BikeComputer.xcodeproj -scheme BikeComputer -configuration Release \
  -destination "id=$SIM" -resultBundlePath "$OUT/uitests.xcresult" -only-testing:BikeComputerUITests \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES > "$OUT/uitest.log" 2>&1
U=$?
digest "$OUT/uitest.log" launch-smoke
if [ $U -eq 0 ]; then note "RESULT launch smoke (Release): ok ($(grep -Eo 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$OUT/uitest.log" | tail -1))"
else
  note "RESULT launch smoke (Release): FAILED (exit $U)"; STATUS=1
  # crash reports of the app from the simulator run, scrubbed, as text
  find "$HOME/Library/Logs/DiagnosticReports" -name 'BikeComputer*' -newer "$OUT/test.log" 2>/dev/null | head -5 | while read -r f; do
    { echo "=== $(basename "$f") ==="; head -c 60000 "$f"; } | scrub >> "$LOGS/crash-reports.txt"
  done
  xcrun simctl spawn "$SIM" log show --last 15m --predicate 'process == "BikeComputer" OR (eventMessage CONTAINS "BikeComputer" AND messageType == error)' 2>/dev/null \
    | grep -v "^Filtering" | tail -400 | scrub > "$LOGS/sim-app-log.txt"
fi

# ---------------------------------------------------------------- archive (device build)
# The archive is ad-hoc signed ("-"): no certificate, no registered device. The entitlements (HealthKit) are embedded
# so the App Store export can re-sign with Apple's cloud-managed distribution certificate.
TEAM_ARGS=()
[ -n "${APPLE_TEAM_ID:-}" ] && TEAM_ARGS=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID")
# account-service configuration → Info.plist (values stay out of the logs; only presence is reported)
CLOUD_ARGS=(SUPABASE_URL="${SUPABASE_URL:-}" SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" GOOGLE_WEB_CLIENT_ID="${GOOGLE_WEB_CLIENT_ID:-}" GOOGLE_IOS_CLIENT_ID="${GOOGLE_IOS_CLIENT_ID:-}" CYCLIFT_SUPPORT_EMAIL="${CYCLIFT_SUPPORT_EMAIL:-}")
if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_ANON_KEY:-}" ]; then note "Accounts: configured (Supabase)$( [ -n "${GOOGLE_WEB_CLIENT_ID:-}" ] && echo ', Google sign-in on' || echo ', Google sign-in off')"
else note "Accounts: not configured (SUPABASE_URL / SUPABASE_ANON_KEY secrets absent) — the app runs guest-only"; fi
ARCHIVE="$OUT/BikeComputer.xcarchive"
archive() {
  local mode=$1; shift
  rm -rf "$ARCHIVE"
  xcodebuild archive -project BikeComputer.xcodeproj -scheme BikeComputer -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
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
note "RESULT archive: ok ($ARCH_MODE)"
for app in "$ARCHIVE/Products/Applications/BikeComputer.app" "$ARCHIVE/Products/Applications/BikeComputer.app/Watch/BikeComputerWatch.app"; do
  if [ -d "$app" ]; then
    DN=$(/usr/libexec/PlistBuddy -c 'Print CFBundleDisplayName' "$app/Info.plist" 2>/dev/null)
    note "  contains $(basename "$app") $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Info.plist")) — display name '$DN'"
    [ "$DN" = "Cyclift" ] || { note "    display name is not Cyclift"; STATUS=1; }
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
note "RESULT upload: ok — build ${BUILD_NUMBER} sent to App Store Connect; TestFlight processing takes about 5-30 minutes"
exit $STATUS
