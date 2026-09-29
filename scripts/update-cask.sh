#!/bin/bash
# Renders the Homebrew cask for a release into OUTFILE (e.g. a tap checkout's
# Casks/sticky-calendar.rb).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: update-cask.sh X.Y.Z SHA256 OUTFILE}"
SHA256="${2:?usage: update-cask.sh X.Y.Z SHA256 OUTFILE}"
OUT="${3:?usage: update-cask.sh X.Y.Z SHA256 OUTFILE}"
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || { echo "error: not a sha256: $SHA256" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
sed -e "s/{{VERSION}}/$VERSION/" -e "s/{{SHA256}}/$SHA256/" packaging/homebrew/sticky-calendar.rb.template > "$OUT"
echo "Wrote $OUT for $VERSION"
