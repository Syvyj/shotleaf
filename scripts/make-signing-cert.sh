#!/bin/bash
# Create the "Shotleaf Local Signing" certificate in the login keychain, so
# scripts/run.sh signs every build the same way and macOS permissions
# (Accessibility, Screen Recording) survive rebuilds. Run once, by hand:
# macOS asks for the keychain password ("Always Allow") on the first build.
set -euo pipefail
NAME="Shotleaf Local Signing"
if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "\"$NAME\" already exists"; exit 0
fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS=$(uuidgen)
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/cert.p12" -passout "pass:$PASS"
security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$PASS" -T /usr/bin/codesign
# Trusted for code signing only (macOS asks for your password).
security add-trusted-cert -r trustRoot -p codeSign \
  -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/cert.pem"
security find-identity -v -p codesigning | grep "$NAME" >/dev/null && echo "\"$NAME\" created"
