#!/usr/bin/env bash
set -euo pipefail

PKG='br.com.lume.bibliotecaestudantil'
ACTIVITY="$PKG/.MainActivity"
QA='artifact/user-journey'
APK='flutter/build/app/outputs/flutter-apk/app-release.apk'
MEDIA="$PWD/journey-media.cbz"
mkdir -p "$QA"

python3 - <<'PY'
import base64,zipfile
png=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
with zipfile.ZipFile('journey-media.cbz','w',zipfile.ZIP_DEFLATED) as z:
    for i in range(1,4): z.writestr(f'page-{i:02}.png',png)
PY

PORT=18787 LUME_JOURNEY_MEDIA="$MEDIA" node tool/user_journey_fixture.js >"$QA/fixture.log" 2>&1 &
SERVER_PID=$!
cleanup(){ if kill -0 "$SERVER_PID" 2>/dev/null; then kill "$SERVER_PID" || true; wait "$SERVER_PID" || true; fi; }
trap cleanup EXIT
for _ in $(seq 1 60); do curl -fsS http://127.0.0.1:18787/v1/health >/dev/null && break; sleep .25; done
curl -fsS http://127.0.0.1:18787/v1/health | tee "$QA/fixture-health.json"

dump_ui(){ adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1; adb exec-out cat /sdcard/window.xml > "$QA/ui-current.xml"; }
coords_for(){
  python3 - "$1" "$QA/ui-current.xml" <<'PY'
import re,sys,xml.etree.ElementTree as ET
needle=sys.argv[1]; root=ET.parse(sys.argv[2]).getroot()
for n in root.iter('node'):
    if n.attrib.get('text')==needle or n.attrib.get('content-desc')==needle:
        m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
        if m:
            x1,y1,x2,y2=map(int,m.groups()); print((x1+x2)//2,(y1+y2)//2); raise SystemExit(0)
raise SystemExit(1)
PY
}
wait_text(){
  local text="$1"; local tries="${2:-80}"
  for _ in $(seq 1 "$tries"); do dump_ui; if coords_for "$text" >/dev/null 2>&1; then return 0; fi; sleep .25; done
  echo "Timed out waiting for UI text: $text" >&2; cp "$QA/ui-current.xml" "$QA/ui-timeout.xml"; return 1
}
tap_text(){
  local text="$1"; wait_text "$text"; local xy; xy="$(coords_for "$text")"; adb shell input tap $xy; sleep .4;
}
snapshot(){ dump_ui; cp "$QA/ui-current.xml" "$QA/ui-$1.xml"; adb exec-out screencap -p > "$QA/$1.png"; }

adb wait-for-device
adb install -r "$APK" | tee "$QA/install.txt"
grep -q '^Success$' "$QA/install.txt"
adb logcat -c
adb shell am force-stop "$PKG"
adb shell am start -W -n "$ACTIVITY" | tee "$QA/launch-online.txt"
grep -q 'Status: ok' "$QA/launch-online.txt"
wait_text 'Entrar'

tap_text 'Usuário'; adb shell input text 'aluno'; sleep .2
tap_text 'Senha'; adb shell input text 'lume2026'; sleep .2
tap_text 'Entrar'
wait_text 'Livros' 120
wait_text 'Clássico da Jornada' 120
wait_text 'Grandes Clássicos'
wait_text 'Essenciais'
snapshot 'catalog-online'

tap_text 'HQs'
wait_text 'HQ Jornada'
wait_text 'Recomendações'
wait_text 'Melhores escritos'
tap_text 'HQ Jornada'
wait_text 'hq-jornada.cbz'
tap_text 'hq-jornada.cbz'
wait_text 'Página 1 de 3' 160
snapshot 'reader-page-1'
adb shell input swipe 900 1100 150 1100 450
wait_text 'Página 2 de 3' 80
sleep 2
snapshot 'reader-page-2'
adb shell input keyevent 4
wait_text 'HQ Jornada'

# Simulate a real outage after the first successful reading session.
kill "$SERVER_PID"; wait "$SERVER_PID" || true
trap - EXIT
sleep 1
if curl -fsS http://127.0.0.1:18787/v1/health >/dev/null 2>&1; then echo 'fixture server still reachable' >&2; exit 81; fi

# Real process death + cold relaunch with backend unavailable.
adb shell am force-stop "$PKG"
sleep 2
adb shell am start -W -n "$ACTIVITY" | tee "$QA/launch-offline.txt"
grep -q 'Status: ok' "$QA/launch-offline.txt"
wait_text 'Livros' 120
if wait_text 'Entrar' 4 >/dev/null 2>&1; then echo 'session was not restored after process restart' >&2; exit 82; fi
snapshot 'catalog-offline-restored'

tap_text 'HQs'
wait_text 'HQ Jornada'
tap_text 'HQ Jornada'
wait_text 'hq-jornada.cbz'
tap_text 'hq-jornada.cbz'
wait_text 'Página 2 de 3' 120
snapshot 'offline-reader-progress-restored'

adb logcat -d -v threadtime > "$QA/logcat.txt"
if grep -q "ANR in $PKG" "$QA/logcat.txt"; then echo 'ANR detected' >&2; exit 83; fi
if grep -q 'FATAL EXCEPTION' "$QA/logcat.txt" && grep -q "Process: $PKG" "$QA/logcat.txt"; then echo 'fatal exception detected' >&2; exit 84; fi
printf '%s\n' 'USER_JOURNEY=pass' 'LOGIN=pass' 'CATALOG=pass' 'CBZ_ONLINE=pass' 'PROCESS_RESTART=pass' 'SECURE_SESSION_RESTORE=pass' 'OFFLINE_CATALOG=pass' 'OFFLINE_CBZ=pass' 'READING_PROGRESS_RESTORE=pass' | tee "$QA/result.txt"
