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

# Flutter's generated Android release template intentionally uses the debug
# signing config until an application provides its own signing material. Keep
# QA builds possible, but make production signing opt-in through key.properties
# generated only in CI/local secure environments. No key material is committed.
s=build.read_text()
needle='''    buildTypes {\n        release {\n            // TODO: Add your own signing config for the release build.\n            // Signing with the debug keys for now, so `flutter run --release` works.\n            signingConfig = signingConfigs.getByName("debug")\n        }\n    }'''
replacement='''    signingConfigs {\n        create("release") {\n            val keyProperties = java.util.Properties()\n            val keyPropertiesFile = rootProject.file("key.properties")\n            if (keyPropertiesFile.exists()) {\n                keyPropertiesFile.inputStream().use { keyProperties.load(it) }\n                keyAlias = keyProperties.getProperty("keyAlias")\n                keyPassword = keyProperties.getProperty("keyPassword")\n                storeFile = file(keyProperties.getProperty("storeFile"))\n                storePassword = keyProperties.getProperty("storePassword")\n            }\n        }\n    }\n\n    buildTypes {\n        release {\n            val keyPropertiesFile = rootProject.file("key.properties")\n            signingConfig = if (keyPropertiesFile.exists()) {\n                signingConfigs.getByName("release")\n            } else {\n                signingConfigs.getByName("debug")\n            }\n        }\n    }'''
if needle not in s:
    raise SystemExit('unexpected Flutter release signing template')
s=s.replace(needle,replacement,1)
build.write_text(s)

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
attrs={
    'android:usesCleartextTraffic':'false',
    'android:allowBackup':'false',
    'android:fullBackupContent':'false',
}
for attr,value in attrs.items():
    if f'{attr}=' not in s:
        s=s.replace('android:label="LUME"',f'android:label="LUME"\n        {attr}="{value}"',1)
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

print(f'Android scaffold hardened: package={PACKAGE}, label=LUME, INTERNET=yes, cleartext=false, backup=false, release-signing=key.properties-or-QA-debug')
