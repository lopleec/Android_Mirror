#!/usr/bin/env bash
# Source this file to resolve a JDK; Android Studio's bundled JDK is also supported.
TASK_JAVA="${JAVA_HOME:-}"
if [[ -z "$TASK_JAVA" && -x '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/javac' ]]; then
  TASK_JAVA='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
fi
if [[ -z "$TASK_JAVA" ]]; then TASK_JAVA="$(/usr/libexec/java_home 2>/dev/null || true)"; fi
if [[ -z "$TASK_JAVA" || ! -x "$TASK_JAVA/bin/javac" ]]; then
  echo 'A JDK is required. Set JAVA_HOME to a JDK 11 or later, or install Android Studio.' >&2
  return 1
fi
