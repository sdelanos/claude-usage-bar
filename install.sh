#!/usr/bin/env bash
#
# One-shot installer for Claude Usage Bar.
#
# Run:
#   curl -fsSL https://raw.githubusercontent.com/sdelanos/claude-usage-bar/main/install.sh | bash
#
# What it does:
#   1. Checks every prerequisite. If anything is missing, it lists ALL of
#      them together with the commands to run, then exits — no iterating
#      back and forth.
#   2. Clones this repo into a temp directory.
#   3. Installs (idempotently) a local code-signing identity in your
#      login keychain so the .app has a stable cryptographic identity.
#   4. Builds the .app, signed with that identity.
#   5. Moves it to /Applications and launches it.
#
# First launch: the dropdown shows a one-time setup card. Run
# `claude setup-token`, paste the printed token, save. No keychain prompts.
#
# Re-run the same one-liner any time to update.

set -euo pipefail

readonly REPO_URL="https://github.com/sdelanos/claude-usage-bar.git"
readonly INSTALL_URL="https://raw.githubusercontent.com/sdelanos/claude-usage-bar/main/install.sh"
readonly APP_NAME="ClaudeUsageBar"
readonly DEST="/Applications/${APP_NAME}.app"

readonly SWIFTLY_INSTALL='curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg && \
installer -pkg swiftly.pkg -target CurrentUserHomeDirectory && \
~/.swiftly/bin/swiftly init --quiet-shell-followup && \
. "${SWIFTLY_HOME_DIR:-$HOME/.swiftly}/env.sh"'

# --- Pretty-print helpers --------------------------------------------------

step() { printf "\033[1;34m▶\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m!\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m✗\033[0m %s\n" "$*" >&2; exit 1; }

# --- Missing-dependency tracker --------------------------------------------

# Parallel arrays so this works on stock macOS Bash 3.2 (no `declare -A`).
MISSING_LABELS=()
MISSING_FIXES=()

add_missing() {
    MISSING_LABELS+=("$1")
    MISSING_FIXES+=("$2")
}

report_missing_and_exit() {
    (( ${#MISSING_LABELS[@]} )) || return 0

    echo
    printf "\033[1;31m✗ Missing prerequisites (%d):\033[0m\n" "${#MISSING_LABELS[@]}"
    for i in "${!MISSING_LABELS[@]}"; do
        echo
        printf "  \033[1m•\033[0m %s\n\n" "${MISSING_LABELS[$i]}"
        printf '%s\n' "${MISSING_FIXES[$i]}" | sed 's/^/      /'
    done
    cat <<EOF

Run the commands above (top to bottom), then re-run:

  curl -fsSL $INSTALL_URL | bash
EOF
    exit 1
}

# --- Checks ----------------------------------------------------------------

step "Checking prerequisites"

# macOS version is fatal on its own — no point listing further deps if the
# OS is too old to run the app.
OS_VER="$(sw_vers -productVersion)"
OS_MAJOR="${OS_VER%%.*}"
if (( OS_MAJOR < 13 )); then
    fail "Requires macOS 13 (Ventura) or later. You're on $OS_VER."
fi
ok "macOS $OS_VER"

# Xcode Command Line Tools — ships git, codesign, security, system openssl.
if ! xcode-select -p >/dev/null 2>&1; then
    add_missing \
        "Xcode Command Line Tools (ships git, codesign, security, openssl)" \
        "xcode-select --install
# Accept the GUI popup that appears, wait for the install to finish."
    CLT_OK=0
else
    ok "Command Line Tools at $(xcode-select -p)"
    CLT_OK=1
fi

# git and openssl come with CLT — only worth checking if CLT is present.
if (( CLT_OK )); then
    if git --version >/dev/null 2>&1; then
        ok "git $(git --version | awk '{print $3}')"
    else
        add_missing "git is on the PATH but doesn't run" \
            "sudo xcode-select --install --force"
    fi

    if command -v openssl >/dev/null 2>&1; then
        ok "openssl: $(openssl version)"
    else
        add_missing "openssl missing (unexpected, should ship with CLT)" \
            "sudo xcode-select --install --force"
    fi
fi

# Swift toolchain. Pulling in Swiftly's env first lets us see a user-level
# install that wasn't sourced in this non-interactive shell.
if [[ -f "$HOME/.swiftly/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.swiftly/env.sh"
fi

if command -v swift >/dev/null 2>&1; then
    ok "Swift: $(swift --version 2>/dev/null | head -1)"
else
    add_missing "Swift 6 toolchain" "$SWIFTLY_INSTALL"
fi

# Claude Code presence — informational, not a build blocker. We don't read
# Claude Code's keychain entry anymore; we just need `claude setup-token` to
# be runnable at first-run setup time.
if command -v claude >/dev/null 2>&1; then
    ok "claude CLI on PATH"
else
    warn "claude CLI not found on PATH."
    warn "Install Claude Code before first-launch setup, otherwise you won't"
    warn "be able to mint a long-lived token via 'claude setup-token'."
    warn "https://docs.claude.com/en/docs/claude-code/overview"
fi

# Bail with the full list if anything's missing.
report_missing_and_exit

echo

# --- Clone -----------------------------------------------------------------

WORK_DIR="$(mktemp -d -t claude-usage-bar-install)"
trap 'rm -rf "$WORK_DIR"' EXIT

step "Cloning $REPO_URL"
git clone --depth 1 --quiet "$REPO_URL" "$WORK_DIR/src"
cd "$WORK_DIR/src"

# This is the catch for the known broken CommandLineTools state: `swift`
# exists but its bundled PackageDescription doesn't link. We can only
# detect it once we have a manifest to parse.
if ! swift package describe >/dev/null 2>&1; then
    cat >&2 <<EOF

$(printf "\033[1;31m✗\033[0m") Your Swift toolchain can't parse SwiftPM manifests.

This is the known CommandLineTools bug in recent macOS releases —
\`swift\` runs but its PackageDescription library is out of sync with its
.swiftinterface. The fix is a side-by-side install of Swiftly (Apple's
official toolchain installer):

EOF
    printf '%s\n' "$SWIFTLY_INSTALL" | sed 's/^/      /' >&2
    cat >&2 <<EOF

Then re-run:

      curl -fsSL $INSTALL_URL | bash
EOF
    exit 1
fi
ok "SwiftPM manifest parses"

# --- Stop running instance -------------------------------------------------

if pgrep -fq "$APP_NAME"; then
    step "Stopping running $APP_NAME"
    killall "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

# --- Code-signing identity (idempotent) -----------------------------------

step "Setting up local code-signing identity"
./setup-cert.sh

# --- Build -----------------------------------------------------------------

step "Building $APP_NAME.app"
./build.sh >/dev/null

# --- Install ---------------------------------------------------------------

if [[ -e "$DEST" ]]; then
    step "Replacing existing $DEST"
    rm -rf "$DEST"
fi

step "Installing to $DEST"
mv "$APP_NAME.app" "$DEST"

# --- Launch ----------------------------------------------------------------

step "Launching $APP_NAME"
open "$DEST"

echo
ok "Done. ClaudeUsageBar is in your menu bar."
echo
echo "  • First launch: click the icon, follow the setup card."
echo "      1. Run 'claude setup-token' in Terminal"
echo "      2. Approve in the browser"
echo "      3. Paste the printed token into the app and Save"
echo "  • To update later: re-run the same install command."
