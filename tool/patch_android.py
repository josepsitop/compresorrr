import pathlib
import re

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

m = pathlib.Path("android/app/src/main/AndroidManifest.xml")
if m.exists():
    s = m.read_text()
    s = re.sub(r'android:label="[^"]*"', 'android:label="Squeeze"', s, count=1)
    m.write_text(s)
print("Android parcheado (minSdk 24, nombre Squeeze)")
