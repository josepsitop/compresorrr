"""Prepara el proyecto Android generado por `flutter create`:
- minSdk 24 y nombre de la app
- código nativo (compartir hacia Squeeze, servicio en segundo plano, datos del equipo)
- permisos, servicio y filtros de "Compartir" en el manifiesto
"""
import pathlib
import re

# --- minSdk 24
for name in ("build.gradle.kts", "build.gradle"):
    f = pathlib.Path("android/app") / name
    if f.exists():
        s = f.read_text()
        kts = name.endswith(".kts")
        s = re.sub(
            r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion",
            "minSdk = 24" if kts else "minSdkVersion 24",
            s,
        )
        f.write_text(s)

# --- código nativo
main = next(pathlib.Path("android/app/src/main").rglob("MainActivity.kt"), None)
if main is None:
    raise SystemExit("No encontré MainActivity.kt")
pkg = re.search(r"^package\s+([\w.]+)", main.read_text(), re.M).group(1)
for tpl, dest in (("MainActivity.kt.tpl", "MainActivity.kt"), ("SqueezeService.kt.tpl", "SqueezeService.kt")):
    code = pathlib.Path("tool/android", tpl).read_text().replace("__PKG__", pkg)
    (main.parent / dest).write_text(code)

# --- manifiesto
m = pathlib.Path("android/app/src/main/AndroidManifest.xml")
s = m.read_text()
s = re.sub(r'android:label="[^"]*"', 'android:label="Squeeze"', s, count=1)
if "SqueezeService" not in s:
    perms = """    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
"""
    s = s.replace("<application", perms + "    <application", 1)
    service = '        <service android:name=".SqueezeService" android:exported="false" android:foregroundServiceType="dataSync"/>\n'
    s = s.replace("</application>", service + "    </application>", 1)
    filters = """            <intent-filter>
                <action android:name="android.intent.action.SEND"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <data android:mimeType="*/*"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.SEND_MULTIPLE"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <data android:mimeType="*/*"/>
            </intent-filter>
"""
    s = s.replace("</activity>", filters + "        </activity>", 1)
m.write_text(s)
print("Android listo: paquete", pkg)
