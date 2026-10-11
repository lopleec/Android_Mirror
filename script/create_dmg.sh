#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
export ANDROID_MIRROR_UNIVERSAL=1
./script/build_and_run.sh --build
TASK_VERSION="$(cat VERSION)"
TASK_APP="$TASK_ROOT/dist/AndroidMirror.app"
TASK_DMG="$TASK_ROOT/dist/AndroidMirror-$TASK_VERSION-macos-universal.dmg"
# A fresh staging directory avoids retaining files from previous versions.
TASK_STAGE="$(mktemp -d "$TASK_ROOT/.build/dmg-stage.XXXXXX")"
/usr/bin/codesign --verify --deep --strict "$TASK_APP"
/usr/bin/lipo "$TASK_APP/Contents/MacOS/AndroidMirror" -verify_arch arm64 x86_64
if [[ -x "$TASK_APP/Contents/Resources/Tools/adb" ]]; then
  /usr/bin/lipo "$TASK_APP/Contents/Resources/Tools/adb" -verify_arch arm64 x86_64
  test -s "$TASK_APP/Contents/Resources/Tools/ADB-NOTICE.txt"
else
  echo 'A universal ADB binary with its NOTICE.txt is required for the downloadable DMG. Set ADB to a macOS Google Platform-Tools executable.' >&2
  exit 1
fi
/usr/bin/ditto --noextattr --noacl "$TASK_APP" "$TASK_STAGE/AndroidMirror.app"
ln -s /Applications "$TASK_STAGE/Applications"
cp LICENSE "$TASK_STAGE/LICENSE.txt"
mkdir "$TASK_STAGE/Third-Party Licenses"
cp Sources/AndroidMirror/Resources/SCRCPY-LICENSE.txt "$TASK_STAGE/Third-Party Licenses/scrcpy-Apache-2.0.txt"
cp "$TASK_APP/Contents/Resources/Tools/ADB-NOTICE.txt" "$TASK_STAGE/Third-Party Licenses/ADB-NOTICE.txt"
cp Assets/Distribution/Read-Me.html "$TASK_STAGE/Read Me.html"
chmod 644 "$TASK_STAGE/LICENSE.txt" "$TASK_STAGE/Read Me.html" "$TASK_STAGE/Third-Party Licenses/"*.txt
/usr/bin/hdiutil create -volname 'Android Mirror' -srcfolder "$TASK_STAGE" -fs HFS+ -format UDZO -ov "$TASK_DMG"
/usr/bin/hdiutil verify "$TASK_DMG"
(cd "$TASK_ROOT/dist" && shasum -a 256 "$(basename "$TASK_DMG")" > SHA256SUMS.txt)
echo "Created: $TASK_DMG"
