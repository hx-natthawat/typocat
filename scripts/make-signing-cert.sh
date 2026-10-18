#!/bin/bash
# Creates a self-signed code-signing certificate, "TypoCat Local Signing", in the
# login keychain. build-app.sh signs with it when it exists, so macOS keeps
# TypoCat's Accessibility access across rebuilds and updates (an ad-hoc signature
# changes every build, and macOS then treats it as a new app).
# It is only trusted for code signing on this Mac; it isn't a Developer ID and
# doesn't stop Gatekeeper's first-open warning on other Macs.
set -euo pipefail
NAME="TypoCat Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists"
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cert.cnf" \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
pass=$(uuidgen)
# macOS's own openssl (LibreSSL) writes a PKCS#12 file the keychain can read.
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$NAME" \
  -out "$work/cert.p12" -passout "pass:$pass"
security import "$work/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$pass" -T /usr/bin/codesign
echo "Created \"$NAME\". Rebuild with ./scripts/build-app.sh, then allow Accessibility once more."
