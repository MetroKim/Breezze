#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required. Install Flutter and add it to PATH." >&2
  exit 1
fi

cd "${APP_DIR}"

# Generate the native runner shells around Breezze's single lib/ codebase.
# Existing Dart source is retained; dependency resolution is intentionally
# left to the caller so this script does not silently update lockfiles.
flutter create \
  --platforms=android,ios,web,linux,macos,windows \
  --project-name=breezze \
  --org=com.breezze \
  --no-pub \
  .


# Configure OS background audio declarations after Flutter generates native runners.
# The repository intentionally keeps one shared Dart app; these are thin native
# service declarations, not separate platform application implementations.
python3 - "${APP_DIR}" <<'PY'
import plistlib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

app_dir = Path(sys.argv[1])
android_ns = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", android_ns)

manifest_path = app_dir / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
if manifest_path.exists():
    tree = ET.parse(manifest_path)
    root = tree.getroot()
    application = root.find("application")
    if application is None:
        raise SystemExit("AndroidManifest.xml has no <application> element")

    def android_attr(name):
        return "{%s}%s" % (android_ns, name)

    permissions = {
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.WAKE_LOCK",
    }
    existing_permissions = {
        node.get(android_attr("name"))
        for node in root.findall("uses-permission")
    }
    for permission in sorted(permissions - existing_permissions):
        node = ET.Element("uses-permission")
        node.set(android_attr("name"), permission)
        root.insert(list(root).index(application), node)

    service_name = "com.ryanheise.audioservice.AudioService"
    if not any(node.get(android_attr("name")) == service_name
               for node in application.findall("service")):
        service = ET.SubElement(application, "service")
        service.set(android_attr("name"), service_name)
        service.set(android_attr("foregroundServiceType"), "mediaPlayback")
        service.set(android_attr("exported"), "true")
        intent = ET.SubElement(service, "intent-filter")
        ET.SubElement(intent, "action").set(
            android_attr("name"), "android.media.browse.MediaBrowserService"
        )

    receiver_name = "com.ryanheise.audioservice.MediaButtonReceiver"
    if not any(node.get(android_attr("name")) == receiver_name
               for node in application.findall("receiver")):
        receiver = ET.SubElement(application, "receiver")
        receiver.set(android_attr("name"), receiver_name)
        receiver.set(android_attr("exported"), "true")
        intent = ET.SubElement(receiver, "intent-filter")
        ET.SubElement(intent, "action").set(
            android_attr("name"), "android.intent.action.MEDIA_BUTTON"
        )

    tree.write(manifest_path, encoding="utf-8", xml_declaration=True)

# audio_service requires the generated Android Activity to use its
# FlutterEngine-aware base class so notification callbacks reach the app.
kotlin_activity = app_dir / "android" / "app" / "src" / "main" / "kotlin" / "com" / "breezze" / "breezze" / "MainActivity.kt"
if kotlin_activity.exists():
    source = kotlin_activity.read_text()
    source = source.replace(
        "import io.flutter.embedding.android.FlutterActivity",
        "import com.ryanheise.audioservice.AudioServiceActivity",
    ).replace(": FlutterActivity()", ": AudioServiceActivity()")
    kotlin_activity.write_text(source)

java_activity = app_dir / "android" / "app" / "src" / "main" / "java" / "com" / "breezze" / "breezze" / "MainActivity.java"
if java_activity.exists():
    source = java_activity.read_text()
    source = source.replace(
        "import io.flutter.embedding.android.FlutterActivity;",
        "import com.ryanheise.audioservice.AudioServiceActivity;",
    ).replace("extends FlutterActivity", "extends AudioServiceActivity")
    java_activity.write_text(source)

ios_plist = app_dir / "ios" / "Runner" / "Info.plist"
if ios_plist.exists():
    with ios_plist.open("rb") as source:
        values = plistlib.load(source)
    modes = values.setdefault("UIBackgroundModes", [])
    if "audio" not in modes:
        modes.append("audio")
    with ios_plist.open("wb") as target:
        plistlib.dump(values, target)

print("Configured Android foreground media service and iOS audio background mode.")
PY
