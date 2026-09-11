#!/usr/bin/env bash
set -euo pipefail

PKG='br.com.lume.bibliotecaestudantil'
ACTIVITY="$PKG/.MainActivity"
APK="$(find artifact -type f -name app-release.apk -print -quit)"
QA='artifact/emulator-qa'

mkdir -p "$QA"
test -n "$APK"
test -f "$APK"
adb wait-for-device
adb shell getprop ro.product.manufacturer | tr -d '\r' > "$QA/manufacturer.txt"
adb shell getprop ro.product.model | tr -d '\r' > "$QA/model.txt"
adb shell getprop ro.build.version.release | tr -d '\r' > "$QA/android-version.txt"
adb shell getprop ro.build.version.sdk | tr -d '\r' > "$QA/api-level.txt"

adb install "$APK" | tee "$QA/install.txt"
grep -q '^Success$' "$QA/install.txt"
adb shell pm path "$PKG" | tee "$QA/package-path.txt"
grep -q '^package:' "$QA/package-path.txt"
adb shell dumpsys package "$PKG" > "$QA/package-dump.txt"
grep -q 'versionCode=38' "$QA/package-dump.txt"
grep -q 'versionName=0.35.3' "$QA/package-dump.txt"

adb logcat -c
adb shell am force-stop "$PKG"
adb shell am start -W -n "$ACTIVITY" | tee "$QA/launch-1.txt"
grep -q 'Status: ok' "$QA/launch-1.txt"
sleep 8
PID1="$(adb shell pidof "$PKG" | tr -d '\r')"
test -n "$PID1"
echo "$PID1" > "$QA/pid-first-launch.txt"
adb exec-out screencap -p > "$QA/first-launch.png"
adb shell dumpsys activity activities > "$QA/activity-first-launch.txt"
grep -q "$PKG" "$QA/activity-first-launch.txt"

adb shell am force-stop "$PKG"
sleep 2
if adb shell pidof "$PKG" | grep -q '[0-9]'; then
  echo 'process survived force-stop unexpectedly' >&2
  exit 71
fi

adb shell am start -W -n "$ACTIVITY" | tee "$QA/launch-2.txt"
grep -q 'Status: ok' "$QA/launch-2.txt"
sleep 8
PID2="$(adb shell pidof "$PKG" | tr -d '\r')"
test -n "$PID2"
echo "$PID2" > "$QA/pid-second-launch.txt"
adb exec-out screencap -p > "$QA/second-launch.png"

adb logcat -d -v threadtime > "$QA/logcat.txt"
if grep -q "ANR in $PKG" "$QA/logcat.txt"; then
  echo 'LUME ANR detected in logcat' >&2
  exit 72
fi
if grep -q 'FATAL EXCEPTION' "$QA/logcat.txt" && grep -q "Process: $PKG" "$QA/logcat.txt"; then
  echo 'LUME fatal exception detected in logcat' >&2
  exit 73
fi

echo 'EMULATOR_SMOKE=pass' | tee "$QA/result.txt"
