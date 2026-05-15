#!/usr/bin/env bash
#
# Print an updated cask formula for a tagged release of claude-usage-bar.
#
# Usage:
#   scripts/bump-cask.sh v0.2.0
#
# Run this AFTER `git push --tags` has finished and the Release workflow
# has published the .zip artifact. The script downloads the artifact,
# computes its SHA256, and prints a fully-substituted cask file to stdout.
# Pipe it into the tap repo:
#
#   scripts/bump-cask.sh v0.2.0 > ../homebrew-claude-usage-bar/Casks/claude-usage-bar.rb
#
# Then commit + push the tap repo.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <tag>   (e.g. v0.2.0)" >&2
    exit 1
fi

TAG="$1"
VERSION="${TAG#v}"
REPO="sdelanos/claude-usage-bar"
ARTIFACT="ClaudeUsageBar-${VERSION}.zip"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ARTIFACT}"

TMP="$(mktemp -d -t claude-usage-bar-bump)"
trap 'rm -rf "$TMP"' EXIT

echo "▶ Fetching $URL" >&2
if ! curl -fsSL --output "$TMP/$ARTIFACT" "$URL"; then
    echo "✗ Couldn't download $URL — is the release published yet?" >&2
    exit 1
fi

SHA="$(shasum -a 256 "$TMP/$ARTIFACT" | awk '{print $1}')"
echo "▶ sha256: $SHA" >&2

TEMPLATE="$(dirname "$0")/../homebrew/Casks/claude-usage-bar.rb"
if [[ ! -f "$TEMPLATE" ]]; then
    echo "✗ Template not found at $TEMPLATE" >&2
    exit 1
fi

# Substitute version + sha into the template. Anchored on the exact
# placeholders the template ships with so a mismatched template fails loud
# instead of producing a broken cask file silently.
sed \
    -e "s|version \"0.0.0\"|version \"${VERSION}\"|" \
    -e "s|sha256 \"0000000000000000000000000000000000000000000000000000000000000000\"|sha256 \"${SHA}\"|" \
    "$TEMPLATE"
