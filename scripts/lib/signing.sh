# Shared by the build scripts. Source it; don't run it.

# Name of the self-signed certificate every release is signed with.
DEFAULT_SIGNING_IDENTITY="Sticky Calendar Self-Signed"

# Prints the SHA-1 of the named code-signing identity, or nothing. Looks in KEYCHAIN if
# given, else in the keychain search list (where codesign looks). A self-signed
# certificate isn't "trusted", so codesign won't find it by name; signing by hash works.
signing_hash() { # NAME [KEYCHAIN]
    security find-identity -p codesigning ${2:+"$2"} 2>/dev/null \
        | awk -v name="\"$1\"" 'index($0, name) { print $2; exit }'
}
