#!/bin/bash
# Cyclift Lab: App Store-signed build + entitlement and isolation check of the SIGNED app. NEVER uploads: this script
# contains no upload step at all, and the .ipa is deleted at the end. Team identifier and e-mail addresses are hidden.
set -uo pipefail
cd "$(dirname "$0")/../../ios"
OUT="$PWD/build/lab-sign"; rm -rf "$OUT"; mkdir -p "$OUT" build/lab-gen
scrub() { sed -E "s/${APPLE_TEAM_ID:-NOTEAM}/<team>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<e-mail hidden>/g"; }
say() { echo "$*" | scrub; }
for k in APPLE_TEAM_ID ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY; do [ -n "${!k:-}" ] || { say "RESULT sign: not possible — Apple credentials are not available to this run"; exit 1; }; done
VERSION=0.1.0; BUILD="${BUILD_NUMBER:-1}"
command -v xcodegen >/dev/null || brew install xcodegen >/dev/null 2>&1
xcodegen generate --spec project-lab.yml > "$OUT/xcodegen.txt" 2>&1 || { say "RESULT generate: FAILED"; exit 1; }
ARCHIVE="$OUT/CycliftLab.xcarchive"
xcodebuild archive -project CycliftLab.xcodeproj -scheme CycliftLab -configuration Release -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -clonedSourcePackagesDirPath build/spm MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$BUILD DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- PROVISIONING_PROFILE_SPECIFIER= CODE_SIGNING_REQUIRED=NO AD_HOC_CODE_SIGNING_ALLOWED=YES > "$OUT/archive.log" 2>&1
if [ $? -ne 0 ]; then say "RESULT Lab archive (Release, device): FAILED"; grep -E " error: " "$OUT/archive.log" | sed -E 's#.*/ios/##' | sort -u | head -20 | scrub; exit 1; fi
say "RESULT Lab archive (Release, device): ok"
KEYDIR=$(mktemp -d); chmod 700 "$KEYDIR"; KEY="$KEYDIR/AuthKey_${ASC_KEY_ID}.p8"
( umask 077; printf '%s\n' "$ASC_PRIVATE_KEY" | sed 's/\\n/\n/g' > "$KEY" )
trap 'rm -rf "$KEYDIR" "$OUT/export" "$OUT/ipa"' EXIT
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
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" > "$OUT/export.log" 2>&1
if [ $? -ne 0 ]; then say "RESULT sign: FAILED"; grep -iE "error|requires|No profiles|agreement" "$OUT/export.log" | sort -u | head -12 | cut -c1-400 | scrub; exit 1; fi
IPA=$(ls "$OUT"/export/*.ipa 2>/dev/null | head -1)
[ -f "$IPA" ] || { say "RESULT sign: FAILED (no .ipa produced)"; exit 1; }
say "RESULT sign: ok (App Store signing, $(stat -f%z "$IPA") bytes)"
mkdir -p "$OUT/ipa"; (cd "$OUT/ipa" && unzip -q "$IPA")
APP="$OUT/ipa/Payload/CycliftLab.app"
codesign --verify --strict "$APP" 2>/dev/null && say "  ok   signature valid" || { say "  FAIL signature invalid"; exit 1; }
codesign -d --entitlements - --xml "$APP" 2>/dev/null > "$OUT/ent.plist"
plutil -convert json -o "$OUT/Info.json" "$APP/Info.plist"
python3 - "$OUT/ent.plist" "$OUT/Info.json" "$APP" "$APPLE_TEAM_ID" "$VERSION" "$BUILD" <<'PY' | scrub
import json, os, plistlib, sys
ent = plistlib.load(open(sys.argv[1], "rb")); info = json.load(open(sys.argv[2])); app, team, version, build = sys.argv[3:7]
BID = "com.ralsuwaidico.cycliftlab"; bad = 0
def check(ok, text):
    global bad
    print(("  ok   " if ok else "  FAIL ") + text); bad += 0 if ok else 1
print("SIGNED APP — entitlements (everything Apple put in the signature):")
for k in sorted(ent): print(f"       {k} = {ent[k]}")
check(ent.get("application-identifier") == f"{team}.{BID}", "application identifier is <team>." + BID)
check(ent.get("get-task-allow") in (None, False), "not a debug build")
groups = ent.get("keychain-access-groups") or []
check(all(g == f"{team}.{BID}" for g in groups), f"keychain: only Lab's own group ({len(groups)} entry)")
forbidden = ["com.apple.developer.healthkit", "com.apple.developer.healthkit.access", "com.apple.developer.healthkit.background-delivery", "com.apple.security.application-groups",
             "com.apple.developer.icloud-container-identifiers", "com.apple.developer.icloud-services", "com.apple.developer.ubiquity-kvstore-identifier",
             "com.apple.developer.ubiquity-container-identifiers", "com.apple.developer.applesignin", "com.apple.developer.associated-domains", "aps-environment",
             "com.apple.developer.in-app-payments", "com.apple.developer.nfc.readersession.formats", "com.apple.external-accessory.wireless-configuration"]
for k in forbidden: check(k not in ent, "absent: " + k)
allowed = {"application-identifier", "com.apple.developer.team-identifier", "get-task-allow", "keychain-access-groups", "beta-reports-active"}
extra = sorted(set(ent) - allowed)
check(not extra, "no entitlement beyond identity, team, keychain and TestFlight feedback" + (f" — found {extra}" if extra else ""))
print("SIGNED APP — Info.plist:")
check(info.get("CFBundleIdentifier") == BID, "identifier " + str(info.get("CFBundleIdentifier")))
check(info.get("CFBundleDisplayName") == "Cyclift Lab", "name on the phone: Cyclift Lab")
check(info.get("CFBundleShortVersionString") == version and str(info.get("CFBundleVersion")) == str(build), f"version {info.get('CFBundleShortVersionString')} build {info.get('CFBundleVersion')}")
for k in ["NSBluetoothAlwaysUsageDescription", "NSBluetoothPeripheralUsageDescription", "NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription",
          "UIBackgroundModes", "CFBundleURLTypes", "SUPABASE_URL", "SUPABASE_ANON_KEY", "GOOGLE_WEB_CLIENT_ID", "GOOGLE_IOS_CLIENT_ID", "CYCLIFT_SUPPORT_EMAIL"]:
    check(k not in info, "absent: " + k)
icon = ((info.get("CFBundleIcons") or {}).get("CFBundlePrimaryIcon") or {}).get("CFBundleIconName")
check(icon == "AppIconLab", "its own icon: " + str(icon))
check(not os.path.exists(os.path.join(app, "Watch")), "no Apple Watch app inside")
check(not os.path.exists(os.path.join(app, "PlugIns")), "no extensions inside")
print("SIGNED ISOLATION RESULT: " + ("ok" if bad == 0 else f"FAILED ({bad})"))
sys.exit(1 if bad else 0)
PY
R=${PIPESTATUS[0]}
say "build identity: Cyclift Lab $VERSION ($BUILD) · commit $(git rev-parse HEAD) · .ipa sha256 $(shasum -a 256 "$IPA" | cut -c1-16)…"
say "RESULT upload: none — this workflow cannot upload; the .ipa is deleted when the run ends"
exit $R
