#!/bin/bash
# Runs on the CI emulator (API 31, 720x1520): installs the APKs, runs the UI flow test, pulls screenshots,
# runs a monkey stress pass and scans logs for crashes. Exit code != 0 fails the job.
set +e
PKG=com.rashed.bikesensordoctor.debug
echo "device-test.sh start $(date)" > progress.txt
adb logcat -c
adb logcat -v time > logcat.txt 2>&1 &
LOGPID=$!
adb shell wm size 720x1520; adb shell wm density 320
adb install -r BikeComputer-build*.apk && echo INSTALL_OK | tee install.txt
adb install -r BikeComputer-test.apk
for perm in BLUETOOTH_SCAN BLUETOOTH_CONNECT ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do adb shell pm grant $PKG android.permission.$perm; done
adb shell settings put secure immersive_mode_confirmations confirmed; adb shell settings put global window_animation_scale 0
adb shell dumpsys package $PKG | grep -E "versionName|versionCode" | tee -a install.txt
echo "installed $(date)" >> progress.txt
adb shell am instrument -w -r -e class com.rashed.bikesensordoctor.AppFlowTest $PKG.test/androidx.test.runner.AndroidJUnitRunner > instrument.txt 2>&1
RC=$?
echo "instrument rc=$RC $(date)" >> progress.txt
tail -5 instrument.txt
mkdir -p screens
adb shell run-as $PKG ls files/screens > screenlist.txt 2>&1; cat screenlist.txt
for f in $(tr -d '\r' < screenlist.txt); do adb exec-out run-as $PKG cat "files/screens/$f" > "screens/$f"; done
ls -la screens | head -60
adb shell run-as $PKG cat files/last-crash.txt > last-crash.txt 2>/dev/null
adb shell dumpsys meminfo $PKG > meminfo.txt 2>&1
echo "pulled $(date)" >> progress.txt
# Stress: 1500 random events must not crash the app
adb shell monkey -p $PKG --pct-syskeys 0 --throttle 60 -s 42 1500 > monkey.txt 2>&1
MRC=$?
tail -3 monkey.txt
adb shell run-as $PKG cat files/last-crash.txt > last-crash-after-monkey.txt 2>/dev/null
sleep 2; kill $LOGPID 2>/dev/null
grep -E "FATAL EXCEPTION|AndroidRuntime: .*Exception" logcat.txt | grep -v systemui | head -50 > crashes.txt
echo "instrument rc=$RC monkey rc=$MRC" | tee -a install.txt
if grep -q "FAILURES!!!\|INSTRUMENTATION_RESULT: shortMsg=Process crashed\|INSTRUMENTATION_FAILED" instrument.txt; then echo "UI TEST FAILED"; RC=1; fi
if [ -s crashes.txt ]; then echo "CRASH IN LOGCAT"; cat crashes.txt; RC=1; fi
if [ -s last-crash-after-monkey.txt ]; then echo "APP CRASH RECORDED"; cat last-crash-after-monkey.txt; RC=1; fi
echo "done rc=$RC $(date)" >> progress.txt
exit $RC
