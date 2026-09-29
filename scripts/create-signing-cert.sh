#!/bin/bash
# One-time setup. Creates the self-signed code-signing certificate, imports it into your
# login keychain, and writes into OUTDIR (keep it private, never commit it):
#   signing-cert.p12          the certificate and its private key
#   signing-cert.p12.base64   value for the SIGNING_CERT_P12 GitHub secret
#   signing-cert.password     value for the SIGNING_CERT_PASSWORD GitHub secret
set -euo pipefail
source "$(dirname "$0")/lib/signing.sh"
OUT="${1:?usage: create-signing-cert.sh OUTDIR}"
NAME="$DEFAULT_SIGNING_IDENTITY"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if [[ -n "$(signing_hash "$NAME" "$KEYCHAIN")" ]]; then
    echo "\"$NAME\" is already in your keychain; not creating another." >&2
    exit 1
fi

mkdir -p "$OUT"
chmod 700 "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null

PASSWORD="$(openssl rand -base64 24)"
# macOS's `security` can't read OpenSSL 3's default PKCS#12 encryption; LibreSSL has no -legacy.
LEGACY=()
openssl version | grep -q LibreSSL || LEGACY=(-legacy)
openssl pkcs12 -export ${LEGACY[@]+"${LEGACY[@]}"} -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$OUT/signing-cert.p12" -passout "pass:$PASSWORD"

security import "$OUT/signing-cert.p12" -k "$KEYCHAIN" \
    -P "$PASSWORD" -T /usr/bin/codesign
base64 -i "$OUT/signing-cert.p12" > "$OUT/signing-cert.p12.base64"
printf '%s' "$PASSWORD" > "$OUT/signing-cert.password"
chmod 600 "$OUT"/signing-cert.*

echo "Created \"$NAME\" and imported it into $KEYCHAIN."
echo "Its SHA-1 is $(signing_hash "$NAME" "$KEYCHAIN"): set RELEASE_CERT_SHA1 in scripts/lib/signing.sh to it."
echo "(A new certificate makes macOS ask existing users for Calendar access again.)"
echo "The first build that uses it may ask to use the key: choose \"Always Allow\"."
echo "GitHub secrets are in $OUT (see RELEASING.md)."
