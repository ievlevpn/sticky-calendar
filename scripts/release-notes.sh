#!/bin/bash
# Prints the release notes for VERSION: its "## VERSION — date" section of CHANGELOG.md,
# without the heading. A release (X.Y.Z) must have a non-empty section, so a changelog
# can't be forgotten; a pre-release (X.Y.Z-suffix) uses its base version's section if
# there is one, or a one-line note.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: release-notes.sh X.Y.Z}"

section() {
    # The lines after "## $1 " up to the next "## ", without leading or trailing blank lines.
    awk -v v="$1" '
        /^## / { if (found) exit; if ($2 == v) { found = 1; next } }
        found { lines[++n] = $0 }
        END {
            first = 1; while (first <= n && lines[first] ~ /^[[:space:]]*$/) first++
            last = n;  while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
            for (i = first; i <= last; i++) print lines[i]
        }' CHANGELOG.md
}

notes="$(section "$VERSION")"
if [[ -n "$notes" ]]; then
    printf '%s\n' "$notes"
elif [[ "$VERSION" == *-* ]]; then
    base="$(section "${VERSION%%-*}")"
    if [[ -n "$base" ]]; then printf '%s\n' "$base"; else echo "Pre-release of ${VERSION%%-*}."; fi
else
    echo "error: CHANGELOG.md has no \"## $VERSION\" section; add one before tagging v$VERSION." >&2
    exit 1
fi
