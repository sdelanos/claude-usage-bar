#!/usr/bin/env bash
#
# Builds ClaudeUsageBar.app from the SwiftPM executable target.
#
# Steps:
#   1. swift build -c release
#   2. Assemble ClaudeUsageBar.app/Contents/{MacOS,Info.plist,Resources}
#   3. Stamp Info.plist's CFBundleShortVersionString from the current git
#      tag (or `CUBAR_VERSION` env var) so the .app's "About" panel and
#      `defaults read .../Info.plist CFBundleShortVersionString` stay in
#      lockstep with the release tag.
#   4. Sign with "ClaudeUsageBar Dev" if available, else fall back to ad-hoc.
#      Stable signing isn't required for the app's auth flow (we use a
#      setup-token in our own keychain item), but it gives the bundle a
#      consistent cryptographic identity macOS can track.

set -euo pipefail

CERT_NAME="ClaudeUsageBar Dev"
APP_NAME="ClaudeUsageBar"
APP_BUNDLE="$APP_NAME.app"
BUILD_CONFIG="release"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Version ----------------------------------------------------------------
# Prefer an explicit CUBAR_VERSION (set by CI from $GITHUB_REF_NAME), fall
# back to `git describe`, fall back to "dev".
if [[ -n "${CUBAR_VERSION:-}" ]]; then
    VERSION="${CUBAR_VERSION#v}"
elif VERSION="$(git describe --tags --abbrev=0 2>/dev/null)"; then
    VERSION="${VERSION#v}"
else
    VERSION="dev"
fi
# Strict semver-ish version for CFBundleShortVersionString; macOS rejects
# anything that doesn't match \d+(\.\d+){0,2}. "dev" → "0.0.0".
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    VERSION="0.0.0"
fi
echo "▶ Building version $VERSION"

# --- Build ------------------------------------------------------------------
echo "▶ Cleaning previous bundle…"
rm -rf "$APP_BUNDLE"

echo "▶ swift build -c $BUILD_CONFIG"
swift build -c "$BUILD_CONFIG"

BIN_PATH="$(swift build -c "$BUILD_CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "❌ Built binary not found at $BIN_PATH" >&2
    exit 1
fi

# --- Bundle -----------------------------------------------------------------
echo "▶ Assembling ${APP_BUNDLE}…"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# Going through SPM's `.process("Resources")` produces an Info.plist-less
# bundle that codesign --deep rejects, so we copy directly.
cp -R Sources/ClaudeUsageBar/Resources/. "$APP_BUNDLE/Contents/Resources/"

# Stamp version into the in-bundle Info.plist. Source Info.plist stays at
# the placeholder so a fresh `swift build` doesn't dirty the working tree.
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $VERSION" \
    "$APP_BUNDLE/Contents/Info.plist"

# --- Sign -------------------------------------------------------------------
echo "▶ Signing…"
# `find-identity -p codesigning` filters out untrusted self-signed identities,
# so check the unfiltered list instead. The cert from setup-cert.sh shows up
# with CSSMERR_TP_NOT_TRUSTED but codesign still accepts it.
if security find-identity ~/Library/Keychains/login.keychain-db 2>/dev/null | grep -q "$CERT_NAME"; then
    codesign --force --deep --options runtime --sign "$CERT_NAME" "$APP_BUNDLE"
    echo "✅ Signed with stable identity '$CERT_NAME'"
else
    echo "⚠️  Identity '$CERT_NAME' not found — falling back to ad-hoc signing."
    echo "⚠️  Run ./setup-cert.sh once to install a stable local identity."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo
codesign -dvv "$APP_BUNDLE" 2>&1 | grep -E "^(Identifier|Authority|TeamIdentifier|Signature)" || true
echo
echo "✅ Built $APP_BUNDLE ($VERSION)"
echo "   Launch with:  open $APP_BUNDLE"
