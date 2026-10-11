#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TASK_ROOT/script/android_tools.sh"
TASK_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
TASK_PLATFORM="${ANDROID_MIRROR_ANDROID_JAR:-}"
TASK_TOOLS="${ANDROID_MIRROR_BUILD_TOOLS:-}"
# Select installed platforms/tools numerically, including preview version names.
if [[ -z "$TASK_PLATFORM" ]]; then
  TASK_PLATFORM="$(python3 - "$TASK_SDK" <<'PY'
import re, sys
from pathlib import Path
items = list((Path(sys.argv[1]) / 'platforms').glob('*/android.jar'))
print(max(items, key=lambda p: tuple(map(int, re.findall(r'\d+', p.parent.name)))), end='') if items else None
PY
)"
fi
if [[ -z "$TASK_TOOLS" ]]; then
  TASK_TOOLS="$(python3 - "$TASK_SDK" <<'PY'
import re, sys
from pathlib import Path
items = [p for p in (Path(sys.argv[1]) / 'build-tools').glob('*') if (p / 'd8').is_file()]
print(max(items, key=lambda p: tuple(map(int, re.findall(r'\d+', p.name)))), end='') if items else None
PY
)"
fi
if [[ ! -f "$TASK_PLATFORM" || ! -x "$TASK_TOOLS/d8" ]]; then
  echo 'Android SDK platform and build-tools are required. Set ANDROID_HOME or ANDROID_SDK_ROOT, then install an SDK platform (API 34+) and build-tools.' >&2
  exit 1
fi
TASK_BUILD="$TASK_ROOT/.build/android-text"
rm -rf "$TASK_BUILD/classes" "$TASK_BUILD/dex"
mkdir -p "$TASK_BUILD/classes" "$TASK_BUILD/dex"
"$TASK_JAVA/bin/javac" --release 8 -Xlint:-options -classpath "$TASK_PLATFORM" -d "$TASK_BUILD/classes" "$TASK_ROOT/AndroidTextService/src/com/lopleec/androidmirror/text/"*.java
JAVA_HOME="$TASK_JAVA" "$TASK_TOOLS/d8" --lib "$TASK_PLATFORM" --min-api 24 --output "$TASK_BUILD/dex" "$TASK_BUILD/classes/com/lopleec/androidmirror/text/"*.class
"$TASK_JAVA/bin/jar" cf "$TASK_ROOT/Sources/AndroidMirror/Resources/android-mirror-text.jar" -C "$TASK_BUILD/dex" classes.dex
python3 "$TASK_ROOT/script/android_text_fingerprint.py" > "$TASK_ROOT/Sources/AndroidMirror/Resources/android-mirror-text.sha256"
echo 'Built the temporary Android text/keyguard service (API 24+).'
