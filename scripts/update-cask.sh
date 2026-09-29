#!/bin/bash
# Renders the Homebrew cask for a release into OUTFILE (e.g. a tap checkout's
# Casks/sticky-calendar.rb).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: update-cask.sh X.Y.Z SHA256 OUTFILE}"
SHA256="${2:?usage: update-cask.sh X.Y.Z SHA256 OUTFILE}"
OUT="${3:?usage: update-cask.sh X.Y.Z SHA256 OUTFILE}"
# Only plain releases go to Homebrew (pre-releases never do); this also keeps sed safe.
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: not a release version (X.Y.Z): $VERSION" >&2; exit 1; }
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || { echo "error: not a sha256: $SHA256" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
# Render to a temporary file first so a failure never leaves a truncated cask behind.
TMP="$(mktemp "$OUT.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
sed -e "s/{{VERSION}}/$VERSION/" -e "s/{{SHA256}}/$SHA256/" packaging/homebrew/sticky-calendar.rb.template > "$TMP"
mv "$TMP" "$OUT"
echo "Wrote $OUT for $VERSION"
