#!/usr/bin/env bash
#
# Build a distributable .app for GitHub Releases.
#
# Differences from build.sh:
#   - Always ad-hoc signs (so users don't need our dev cert).
#   - Zips the bundle with `ditto` (the only way to keep macOS metadata
#     intact through GitHub Release upload + download).
#   - Prints the SHA256, which is what the Homebrew cask formula needs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="ClaudeUsageBar"
APP_BUNDLE="$APP_NAME.app"
RELEASE_DIR="dist"
ZIP_PATH="$RELEASE_DIR/${APP_NAME}.zip"

echo "▶ Cleaning previous artifacts…"
rm -rf "$APP_BUNDLE" "$RELEASE_DIR"

echo "▶ swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "❌ Built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "▶ Assembling ${APP_BUNDLE}…"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp -R Sources/ClaudeUsageBar/Resources/. "$APP_BUNDLE/Contents/Resources/"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "▶ Ad-hoc signing for distribution…"
codesign --force --deep --options runtime --sign - "$APP_BUNDLE"

mkdir -p "$RELEASE_DIR"
echo "▶ Packaging $ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

SIZE=$(du -h "$ZIP_PATH" | cut -f1)
SHA=$(shasum -a 256 "$ZIP_PATH" | cut -d' ' -f1)

echo
echo "✅ Release artifact ready"
echo "   File:    $ZIP_PATH"
echo "   Size:    $SIZE"
echo "   SHA256:  $SHA"
echo
echo "Next steps:"
echo "  1. Tag this commit (e.g. git tag v0.1.0) and push the tag."
echo "  2. Create a GitHub Release for that tag and attach $ZIP_PATH."
echo "  3. In the homebrew-claude-usage-bar repo, bump the cask version + sha256:"
echo "       version \"<new>\""
echo "       sha256 \"$SHA\""
echo "     Then commit & push."
