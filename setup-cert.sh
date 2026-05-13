#!/usr/bin/env bash
#
# Generates a self-signed code-signing certificate named "ClaudeUsageBar Dev",
# bundles it as a .p12 (legacy format — macOS Keychain rejects OpenSSL 3's
# default AES-256 MAC), and imports it into the login keychain so codesign
# can use it.
#
# Re-runnable: deletes any prior "ClaudeUsageBar Dev" identity before importing.
#
# Steps:
#   1. openssl genrsa             → RSA 2048 private key
#   2. openssl req -x509          → self-signed X.509 cert with codeSigning EKU
#   3. openssl pkcs12 -export     → .p12 with -legacy (mandatory)
#   4. security import            → into login.keychain-db, ACL'd for codesign + security
#   5. security add-trusted-cert  → optional, marks the cert trusted for codeSign
#   6. security find-identity     → sanity check

set -euo pipefail

CERT_NAME="ClaudeUsageBar Dev"
WORK_DIR="$(mktemp -d -t claudeusagebar-cert)"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
P12_PASSWORD="tmp"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cd "$WORK_DIR"

echo "▶ Working dir: $WORK_DIR"
echo "▶ Generating RSA 2048 private key…"
openssl genrsa -out key.pem 2048 2>/dev/null

cat > openssl.cnf <<EOF
[ req ]
distinguished_name = req_distinguished_name
prompt             = no
x509_extensions    = v3_ca

[ req_distinguished_name ]
CN = $CERT_NAME

[ v3_ca ]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
EOF

echo "▶ Generating self-signed code-signing certificate (10 years)…"
openssl req \
  -x509 \
  -new \
  -key key.pem \
  -out cert.pem \
  -days 3650 \
  -config openssl.cnf \
  -extensions v3_ca \
  -sha256 2>/dev/null

echo "▶ Bundling as PKCS#12 (legacy MAC — required for macOS Keychain)…"
openssl pkcs12 -export \
  -legacy \
  -inkey key.pem \
  -in cert.pem \
  -name "$CERT_NAME" \
  -password "pass:$P12_PASSWORD" \
  -out cert.p12

# Remove any prior identity with the same name to keep this script idempotent.
# `security delete-identity` only exists in newer macOS; fall back to delete-certificate.
echo "▶ Removing any existing '$CERT_NAME' identity…"
security delete-identity -c "$CERT_NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true
security delete-certificate -c "$CERT_NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true

echo "▶ Importing into login keychain (you may be prompted to allow keychain access)…"
security import cert.p12 \
  -k "$LOGIN_KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/productsign

# Unlock so the import is usable in the same shell session.
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s -k "" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true

# Optional: mark the cert as trusted for code signing. Requires sudo.
echo "▶ Marking certificate trusted for code signing (requires sudo)…"
if sudo -n true 2>/dev/null; then
  sudo security add-trusted-cert -d -r trustRoot -p codeSign \
    -k /Library/Keychains/System.keychain cert.pem || true
else
  echo "  (sudo not cached; you'll be prompted once)"
  sudo security add-trusted-cert -d -r trustRoot -p codeSign \
    -k /Library/Keychains/System.keychain cert.pem || true
fi

echo "▶ Verifying identity is available to codesign…"
# `security find-identity -v` filters out untrusted self-signed certs, so probe
# with a real codesign on a throwaway file instead. That's the only check that
# matches what build.sh actually does.
PROBE="$(mktemp -t claudeusagebar-probe)"
printf '#!/bin/sh\nexit 0\n' > "$PROBE"
chmod +x "$PROBE"
if codesign --force --sign "$CERT_NAME" "$PROBE" 2>/dev/null; then
  rm -f "$PROBE"
  security find-identity "$LOGIN_KEYCHAIN" | grep "$CERT_NAME" || true
  echo
  echo "✅ '$CERT_NAME' is now available as a code signing identity."
  echo "   (Reported as CSSMERR_TP_NOT_TRUSTED — that's expected for a self-signed cert"
  echo "    and does not prevent codesign from using it.)"
else
  rm -f "$PROBE"
  echo "❌ codesign cannot use '$CERT_NAME' after import. Check security errors above." >&2
  exit 1
fi
