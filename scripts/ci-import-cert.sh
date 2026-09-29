#!/bin/bash
# CI only (fresh runner). Imports the signing certificate from the SIGNING_CERT_P12 (base64)
# and SIGNING_CERT_PASSWORD secrets into a temporary keychain codesign can use unattended.
set -euo pipefail
: "${SIGNING_CERT_P12:?secret SIGNING_CERT_P12 is not set}"
: "${SIGNING_CERT_PASSWORD:?secret SIGNING_CERT_PASSWORD is not set}"
: "${RUNNER_TEMP:?not running on GitHub Actions}"

KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 24)"
printf '%s' "$SIGNING_CERT_P12" | base64 --decode > "$RUNNER_TEMP/signing-cert.p12"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$RUNNER_TEMP/signing-cert.p12" -k "$KEYCHAIN" -P "$SIGNING_CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# codesign only finds identities in keychains on the search list.
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
rm "$RUNNER_TEMP/signing-cert.p12"
security find-identity -p codesigning "$KEYCHAIN"
