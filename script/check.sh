#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
python3 script/verify_localizations.py
swift test --scratch-path "${ANDROID_MIRROR_BUILD_PATH:-$TASK_ROOT/.build/swiftpm}" --cache-path "$TASK_ROOT/.build/cache" -Xswiftc -module-cache-path -Xswiftc "$TASK_ROOT/.build/module-cache"
# This is a pure Java text-edit check, without a phone or Android framework.
source "$TASK_ROOT/script/android_tools.sh"
mkdir -p "$TASK_ROOT/.build/java-tests"
"$TASK_JAVA/bin/javac" --release 8 -Xlint:-options -d "$TASK_ROOT/.build/java-tests" \
  AndroidTextService/src/com/lopleec/androidmirror/text/EditableText.java Tests/AndroidTextService/TextEditTest.java
"$TASK_JAVA/bin/java" -cp "$TASK_ROOT/.build/java-tests" com.lopleec.androidmirror.text.TextEditTest
