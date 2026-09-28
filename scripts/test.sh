#!/bin/bash
# Runs the unit tests. With only the Command Line Tools installed (no Xcode),
# Swift Testing lives outside the default search paths, so point swift at it.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV="$(xcode-select -p)"
FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"

if [[ -d "$FW/Testing.framework" ]]; then
    exec swift test \
        -Xswiftc -F -Xswiftc "$FW" \
        -Xlinker -rpath -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$LIB" \
        "$@"
else
    exec swift test "$@"
fi
