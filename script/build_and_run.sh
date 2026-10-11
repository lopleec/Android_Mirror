#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="AndroidMirror"
BUNDLE_ID="com.lopleec.androidmirror"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
UNIVERSAL="${ANDROID_MIRROR_UNIVERSAL:-0}"
SWIFT_BUILD_PATH="${ANDROID_MIRROR_BUILD_PATH:-$ROOT_DIR/.build/swiftpm}"
if [[ "$UNIVERSAL" == "1" ]]; then SWIFT_BUILD_PATH="${ANDROID_MIRROR_BUILD_PATH:-$ROOT_DIR/.build/universal}"; fi
APP_VERSION="$(cat "$ROOT_DIR/VERSION")"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo 'VERSION must contain major.minor.patch.' >&2; exit 2; fi

if [[ "$MODE" != "--build" ]]; then pkill -x "$APP_NAME" >/dev/null 2>&1 || true; fi
TEXT_JAR="$ROOT_DIR/Sources/AndroidMirror/Resources/android-mirror-text.jar"
TEXT_HASH="$ROOT_DIR/Sources/AndroidMirror/Resources/android-mirror-text.sha256"
SOURCE_HASH="$(python3 "$ROOT_DIR/script/android_text_fingerprint.py")"
if [[ ! -f "$TEXT_JAR" || ! -f "$TEXT_HASH" || "$(cat "$TEXT_HASH")" != "$SOURCE_HASH" ]]; then
  "$ROOT_DIR/script/build_android_text.sh"
fi
python3 "$ROOT_DIR/script/verify_localizations.py"
BUILD_CONFIGURATION="release"
if [[ "$MODE" == "--debug" ]]; then BUILD_CONFIGURATION="debug"; fi
if [[ "$UNIVERSAL" == "1" ]]; then
  for BUILD_ARCH in arm64 x86_64; do
    BUILD_TRIPLE="$BUILD_ARCH-apple-macosx14.0"
    ARCH_BUILD_PATH="$SWIFT_BUILD_PATH/$BUILD_ARCH"
    swift build -c "$BUILD_CONFIGURATION" --triple "$BUILD_TRIPLE" --scratch-path "$ARCH_BUILD_PATH" --cache-path "$ROOT_DIR/.build/cache" -Xswiftc -module-cache-path -Xswiftc "$ROOT_DIR/.build/module-cache"
    ARCH_BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --triple "$BUILD_TRIPLE" --scratch-path "$ARCH_BUILD_PATH" --show-bin-path)"
    if [[ "$BUILD_ARCH" == "arm64" ]]; then
      BIN_DIR="$ARCH_BIN_DIR"; ARM_BINARY="$ARCH_BIN_DIR/$APP_NAME"
    else
      INTEL_BINARY="$ARCH_BIN_DIR/$APP_NAME"
    fi
  done
  /usr/bin/lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$SWIFT_BUILD_PATH/$APP_NAME"
  APP_BINARY="$SWIFT_BUILD_PATH/$APP_NAME"
else
  swift build -c "$BUILD_CONFIGURATION" --scratch-path "$SWIFT_BUILD_PATH" --cache-path "$ROOT_DIR/.build/cache" -Xswiftc -module-cache-path -Xswiftc "$ROOT_DIR/.build/module-cache"
  BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --scratch-path "$SWIFT_BUILD_PATH" --show-bin-path)"
  APP_BINARY="$BIN_DIR/$APP_NAME"
fi
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/Tools"
cp "$ROOT_DIR/LICENSE" "$CONTENTS/Resources/LICENSE-MIT.txt"
cp "$APP_BINARY" "$CONTENTS/MacOS/$APP_NAME"
rm -rf "$CONTENTS/Resources/AndroidMirror_AndroidMirror.bundle"
cp -R "$BIN_DIR/AndroidMirror_AndroidMirror.bundle" "$CONTENTS/Resources/"
for APP_LANGUAGE in en zh-Hans; do
  mkdir -p "$CONTENTS/Resources/$APP_LANGUAGE.lproj"
  cp "$ROOT_DIR/Assets/Localization/$APP_LANGUAGE.lproj/InfoPlist.strings" "$CONTENTS/Resources/$APP_LANGUAGE.lproj/"
done
# Do not retain an ADB binary from a previous build when no source is selected.
rm -f "$CONTENTS/Resources/Tools/adb" "$CONTENTS/Resources/Tools/ADB-NOTICE.txt"

ADB_SOURCE="${ADB:-}"
if [[ -z "$ADB_SOURCE" ]]; then ADB_SOURCE="$(command -v adb || true)"; fi
if [[ -z "$ADB_SOURCE" && -x "$HOME/Documents/Android/platform-tools/adb" ]]; then ADB_SOURCE="$HOME/Documents/Android/platform-tools/adb"; fi
if [[ -z "$ADB_SOURCE" && -x "$HOME/Library/Android/sdk/platform-tools/adb" ]]; then ADB_SOURCE="$HOME/Library/Android/sdk/platform-tools/adb"; fi
if [[ -n "$ADB_SOURCE" && -x "$ADB_SOURCE" ]]; then
  cp "$ADB_SOURCE" "$CONTENTS/Resources/Tools/adb"
  chmod +x "$CONTENTS/Resources/Tools/adb"
  ADB_NOTICE="$(dirname "$ADB_SOURCE")/NOTICE.txt"
  if [[ -f "$ADB_NOTICE" ]]; then cp "$ADB_NOTICE" "$CONTENTS/Resources/Tools/ADB-NOTICE.txt"; fi
fi
if [[ -f "$ROOT_DIR/Assets/AppIcon-Source.png" ]] &&
   [[ ! -f "$ROOT_DIR/Assets/AppIcon.icns" || "$ROOT_DIR/Assets/AppIcon-Source.png" -nt "$ROOT_DIR/Assets/AppIcon.icns" || "$ROOT_DIR/script/create_icon.swift" -nt "$ROOT_DIR/Assets/AppIcon.icns" ]]; then
  swift -module-cache-path "$ROOT_DIR/.build/module-cache" "$ROOT_DIR/script/create_icon.swift" "$ROOT_DIR/Assets/AppIcon-Source.png" "$ROOT_DIR/Assets/AppIcon-1024.png"
fi
ICON_NAME="AppIcon"
if [[ -f "$ROOT_DIR/Assets/AppIcon.icns" ]]; then
  # A new resource name invalidates the cached Finder icon when the artwork changes.
  ICON_HASH="$(shasum -a 256 "$ROOT_DIR/Assets/AppIcon.icns" | cut -c 1-12)"
  ICON_NAME="AppIcon-$ICON_HASH"
  rm -f "$CONTENTS/Resources/"AppIcon*.icns
  cp "$ROOT_DIR/Assets/AppIcon.icns" "$CONTENTS/Resources/$ICON_NAME.icns"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AndroidMirror</string>
<key>CFBundleIdentifier</key><string>com.lopleec.androidmirror</string>
<key>CFBundleName</key><string>Android Mirror</string>
<key>CFBundleDisplayName</key><string>Android Mirror</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>$ICON_NAME</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Discover and connect to Android phones on the same Wi-Fi for wireless debugging pairing and mirroring.</string>
<key>NSBonjourServices</key><array><string>_adb-tls-pairing._tcp</string><string>_adb-tls-connect._tcp</string></array>
</dict></plist>
PLIST

# Distribution files must be readable by other macOS user accounts.
chmod -R u+rwX,go+rX "$APP_BUNDLE"
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
touch "$APP_BUNDLE"
LS_REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LS_REGISTER" ]]; then "$LS_REGISTER" -f "$APP_BUNDLE"; fi
case "$MODE" in
  --build) echo "Built: $APP_BUNDLE" ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 2; pgrep -x "$APP_NAME" >/dev/null; echo "App is running." ;;
  --debug) lldb -- "$CONTENTS/MacOS/$APP_NAME" ;;
  --logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "AndroidMirror"' ;;
  --telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.lopleec.androidmirror"' ;;
  *) echo "usage: $0 [run|--build|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
