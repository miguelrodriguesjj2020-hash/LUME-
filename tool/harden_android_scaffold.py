#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
ANDROID=ROOT/'flutter'/'android'
PACKAGE='br.com.lume.bibliotecaestudantil'
OLD='com.example.lume'


def replace_once(path,old,new):
    p=Path(path); s=p.read_text()
    count=s.count(old)
    if count!=1:
        raise SystemExit(f'{p}: expected exactly one occurrence of {old!r}, found {count}')
    p.write_text(s.replace(old,new,1))

build=ANDROID/'app'/'build.gradle.kts'
replace_once(build,f'namespace = "{OLD}"',f'namespace = "{PACKAGE}"')
replace_once(build,f'applicationId = "{OLD}"',f'applicationId = "{PACKAGE}"')

manifest=ANDROID/'app'/'src'/'main'/'AndroidManifest.xml'
s=manifest.read_text()
if 'android.permission.INTERNET' not in s:
    needle='<application'
    if s.count(needle)!=1:
        raise SystemExit('unexpected main AndroidManifest application count')
    s=s.replace(needle,'<uses-permission android:name="android.permission.INTERNET" />\n    '+needle,1)
if 'android:label="lume"' in s:
    s=s.replace('android:label="lume"','android:label="LUME"',1)
elif 'android:label="LUME"' not in s:
    raise SystemExit('unexpected Android application label')
if 'android:usesCleartextTraffic=' not in s:
    s=s.replace('android:label="LUME"','android:label="LUME"\n        android:usesCleartextTraffic="false"',1)
manifest.write_text(s)

old_activity=ANDROID/'app'/'src'/'main'/'kotlin'/'com'/'example'/'lume'/'MainActivity.kt'
if not old_activity.exists():
    matches=list((ANDROID/'app'/'src'/'main'/'kotlin').rglob('MainActivity.kt'))
    if len(matches)!=1:
        raise SystemExit(f'expected one MainActivity.kt, found {len(matches)}')
    old_activity=matches[0]
activity=old_activity.read_text()
if f'package {OLD}' not in activity:
    raise SystemExit('unexpected MainActivity package declaration')
activity=activity.replace(f'package {OLD}',f'package {PACKAGE}',1)
new_activity=ANDROID/'app'/'src'/'main'/'kotlin'/Path(*PACKAGE.split('.'))/'MainActivity.kt'
new_activity.parent.mkdir(parents=True,exist_ok=True)
new_activity.write_text(activity)
if old_activity.resolve()!=new_activity.resolve():
    old_activity.unlink()

print(f'Android scaffold hardened: package={PACKAGE}, label=LUME, INTERNET=yes, cleartext=false')
