# Shared by the build scripts. Source it; don't run it.

# Name of the self-signed certificate every release is signed with.
DEFAULT_SIGNING_IDENTITY="Sticky Calendar Self-Signed"

# SHA-1 of that exact certificate. Releases must be signed with it: users' Calendar
# permission is tied to it, so a different certificate — even with the same name — would
# make macOS ask every user again. Replacing it is a deliberate change to this line.
# (Overridable only to test the release checks.)
RELEASE_CERT_SHA1="${RELEASE_CERT_SHA1:-8FDA45D7C583C359AB53200C7B7CB3CE84295A91}"

# Whether the release certificate is in the keychain search list.
has_release_cert() {
    local identities
    identities="$(security find-identity -p codesigning 2>/dev/null)"
    [[ "$identities" == *"$RELEASE_CERT_SHA1"* ]]
}

# Prints the SHA-1 of the named code-signing identity, or nothing. Looks in KEYCHAIN if
# given, else in the keychain search list (where codesign looks). A self-signed
# certificate isn't "trusted", so codesign won't find it by name; signing by hash works.
signing_hash() { # NAME [KEYCHAIN]
    security find-identity -p codesigning ${2:+"$2"} 2>/dev/null \
        | awk -v name="\"$1\"" 'index($0, name) { print $2; exit }'
}
