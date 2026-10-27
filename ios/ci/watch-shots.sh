#!/usr/bin/env bash
# Apple Watch layout screenshots (quality release, soft check — never fails the run): builds the watch app for the
# watchOS simulator, launches it on the smallest and the largest Apple Watch simulator of the newest runtime at the
# default (L), XXXL and AX3 text sizes and saves PNGs as watch-<small|large>-<size>.png into the layout folder.
# The watch app shows no personal data without a paired iPhone.
set -uo pipefail
cd "$(dirname "$0")/.."
DEST=${1:-build/layout}
mkdir -p "$DEST" build/logs
LOG=build/logs/watch-shots.txt
: > "$LOG"
if ! xcodebuild build -project BikeComputer.xcodeproj -target BikeComputerWatch -configuration Debug -sdk watchsimulator \
     SYMROOT="$PWD/build/wsym" CODE_SIGNING_ALLOWED=NO > build/watch-build.log 2>&1; then
  { echo "watch simulator build failed"; grep -E "error:" build/watch-build.log | sort -u | head -20; } >> "$LOG"; exit 0
fi
APP=$(ls -d build/wsym/Debug-watchsimulator/*.app 2>/dev/null | head -1)
[ -n "$APP" ] || { echo "no watch app built" >> "$LOG"; exit 0; }
BID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
WATCHES=$(xcrun simctl list devices available -j | python3 -c '
import json,sys,re
d=json.load(sys.stdin)["devices"]; a=[]
for rt,devs in d.items():
    if ".watchOS-" not in rt: continue
    ver=tuple(int(x) for x in rt.split(".watchOS-")[1].split("-"))
    for x in devs:
        m=re.search(r"(\d+)\s*mm", x["name"])
        if m: a.append((ver,int(m.group(1)),x["udid"],x["name"]))
if a:
    v=max(t[0] for t in a); a=[t for t in a if t[0]==v]
    s=min(a,key=lambda t:t[1]); l=max(a,key=lambda t:t[1])
    print("small|"+s[2]+"|"+s[3])
    if l[2]!=s[2]: print("large|"+l[2]+"|"+l[3])')
[ -n "$WATCHES" ] || { echo "no Apple Watch simulator available" >> "$LOG"; exit 0; }
while IFS='|' read -r WN WU WNAME; do
  echo "$WN: $WNAME" >> "$LOG"
  xcrun simctl boot "$WU" >/dev/null 2>&1 || true
  for i in $(seq 1 60); do xcrun simctl list devices -j | grep -A3 "\"$WU\"" | grep -q '"Booted"' && break; sleep 2; done
  sleep 10
  xcrun simctl install "$WU" "$APP" >> "$LOG" 2>&1 || { echo "  install failed" >> "$LOG"; continue; }
  for spec in "l|large|UICTContentSizeCategoryL" "xxxl|extra-extra-extra-large|UICTContentSizeCategoryXXXL" "ax3|accessibility-extra-large|UICTContentSizeCategoryAccessibilityXL"; do
    IFS='|' read -r TAG UI CAT <<< "$spec"
    xcrun simctl terminate "$WU" "$BID" >/dev/null 2>&1 || true
    xcrun simctl ui "$WU" content_size "$UI" >/dev/null 2>&1 || echo "  content_size $UI not supported here" >> "$LOG"
    xcrun simctl launch "$WU" "$BID" -UIPreferredContentSizeCategoryName "$CAT" >> "$LOG" 2>&1 || { echo "  launch failed" >> "$LOG"; continue; }
    sleep 8
    xcrun simctl io "$WU" screenshot "$DEST/watch-$WN-$TAG.png" >/dev/null 2>&1 && echo "  screenshot $TAG ok" >> "$LOG" || echo "  screenshot $TAG failed" >> "$LOG"
  done
  xcrun simctl shutdown "$WU" >/dev/null 2>&1 || true
done <<< "$WATCHES"
exit 0
