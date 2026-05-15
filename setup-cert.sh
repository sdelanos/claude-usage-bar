#!/usr/bin/env bash
#
# Installs a self-signed code-signing identity named "ClaudeUsageBar Dev"
# into your login keychain. build.sh then signs the .app with it so the
# bundle has a stable cryptographic identity — useful for any future
# macOS subsystem that tracks apps by signature (TCC permissions, the
# data-protection keychain, etc.).
#
# Note: as of the setup-token-based auth flow, the app no longer reads
# Claude Code's keychain entry, so this identity is no longer required to
# avoid recurring "Always Allow" prompts. It's still recommended though —
# ad-hoc signed binaries look like a new app on every rebuild, which can
# trigger unrelated re-prompts (e.g. Gatekeeper, future TCC permissions).
#
# Idempotent: if a usable "ClaudeUsageBar Dev" identity already exists,
# this script exits cleanly without touching the keychain.

set -euo pipefail

CERT_NAME="ClaudeUsageBar Dev"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# Random per-run password for the in-flight .p12. The bundle is deleted
# on EXIT via the trap below, so the password protects only the on-disk
# intermediate before keychain import.
P12_PASSWORD="$(openssl rand -base64 16 | tr -d '/+=')"

# Prefer Homebrew's OpenSSL 3 (supports `-legacy`) when present; fall back to
# the system openssl (LibreSSL on macOS, which produces a Keychain-compatible
# .p12 by default and doesn't recognize `-legacy`).
if [[ -x /opt/homebrew/bin/openssl ]]; then
    OPENSSL="/opt/homebrew/bin/openssl"
elif [[ -x /usr/local/bin/openssl ]]; then
    OPENSSL="/usr/local/bin/openssl"
else
    OPENSSL="openssl"
fi

P12_LEGACY_ARGS=()
if "$OPENSSL" version | grep -q '^OpenSSL 3'; then
    # OpenSSL 3's default PKCS#12 uses an AES-256 MAC macOS Keychain rejects.
    P12_LEGACY_ARGS=(-legacy)
fi

# --- Idempotency: skip everything if the identity is already usable. -------

probe_existing() {
    local probe
    probe="$(mktemp -t claudeusagebar-probe)"
    printf '#!/bin/sh\nexit 0\n' > "$probe"
    chmod +x "$probe"
    if codesign --force --sign "$CERT_NAME" "$probe" 2>/dev/null; then
        rm -f "$probe"
        return 0
    fi
    rm -f "$probe"
    return 1
}

if probe_existing; then
    echo "✅ '$CERT_NAME' is already installed and usable. Nothing to do."
    exit 0
fi

# --- Fresh install ---------------------------------------------------------

WORK_DIR="$(mktemp -d -t claudeusagebar-cert)"
trap "rm -rf $WORK_DIR" EXIT

cd "$WORK_DIR"

echo "▶ Generating RSA 2048 private key…"
"$OPENSSL" genrsa -out key.pem 2048 2>/dev/null

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
"$OPENSSL" req \
    -x509 \
    -new \
    -key key.pem \
    -out cert.pem \
    -days 3650 \
    -config openssl.cnf \
    -extensions v3_ca \
    -sha256 2>/dev/null

echo "▶ Bundling as PKCS#12 (macOS-compatible MAC)…"
"$OPENSSL" pkcs12 -export \
    "${P12_LEGACY_ARGS[@]}" \
    -inkey key.pem \
    -in cert.pem \
    -name "$CERT_NAME" \
    -password "pass:$P12_PASSWORD" \
    -out cert.p12

# Sweep any leftover entries with the same name (broken installs, etc.)
echo "▶ Cleaning any stale '$CERT_NAME' entries…"
security delete-identity -c "$CERT_NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true
security delete-certificate -c "$CERT_NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true

echo "▶ Importing into login keychain…"
security import cert.p12 \
    -k "$LOGIN_KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -T /usr/bin/productsign

# Allow tools in the ACL above to use the key without re-prompting.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true

echo "▶ Verifying identity is usable for codesign…"
if probe_existing; then
    security find-identity "$LOGIN_KEYCHAIN" | grep "$CERT_NAME" || true
    echo
    echo "✅ '$CERT_NAME' is installed."
    echo "   (Reported as CSSMERR_TP_NOT_TRUSTED — that's expected for a self-signed"
    echo "    cert and does not prevent codesign from using it.)"
else
    echo "❌ codesign cannot use '$CERT_NAME' after import. Check errors above." >&2
    exit 1
fi
