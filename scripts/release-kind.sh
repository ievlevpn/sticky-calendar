#!/bin/bash
# Classifies a release tag: prints "release" for vX.Y.Z, "prerelease" for vX.Y.Z-suffix,
# and fails for anything else, so a mistyped tag never publishes a release.
set -euo pipefail
TAG="${1:?usage: release-kind.sh TAG}"
if [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo release
elif [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z.]+$ ]]; then
    echo prerelease
else
    echo "error: tag \"$TAG\" is not vX.Y.Z or vX.Y.Z-suffix" >&2
    exit 1
fi
