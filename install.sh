#!/usr/bin/env bash
#
# One-shot installer for Claude Usage Bar.
#
# Run:
#   curl -fsSL https://raw.githubusercontent.com/sdelanos/claude-usage-bar/main/install.sh | bash
#
# What it does:
#   1. Checks every prerequisite (macOS version, Command Line Tools, git,
#      Swift toolchain, openssl, Claude Code credentials).
#   2. Clones this repo into a temp directory.
#   3. Installs (idempotently) a local code-signing identity in your login
#      keychain — this is what lets macOS remember the Claude Code Keychain
#      "Always Allow" decision after the first launch.
#   4. Builds the .app, signed with that identity.
#   5. Moves it to /Applications and launches it.
#
# Re-run the same one-liner any time to update.

set -euo pipefail

REPO_URL="https://github.com/sdelanos/claude-usage-bar.git"
APP_NAME="ClaudeUsageBar"
DEST="/Applications/${APP_NAME}.app"

step() { printf "\033[1;34m▶\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m!\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m✗\033[0m %s\n" "$*" >&2; exit 1; }

step "Checking prerequisites"

# --- macOS version ---------------------------------------------------------

OS_VER="$(sw_vers -productVersion)"
OS_MAJOR="${OS_VER%%.*}"
if (( OS_MAJOR < 13 )); then
    fail "Need macOS 13 (Ventura) or later. You're on $OS_VER."
fi
ok "macOS $OS_VER"

# --- Command Line Tools (provides git, codesign, security, system openssl) -

if ! xcode-select -p >/dev/null 2>&1; then
    fail "Command Line Tools not installed.

Run this in a terminal, accept the GUI popup, wait for it to finish,
then re-run this installer:

    xcode-select --install"
fi
ok "Command Line Tools at $(xcode-select -p)"

# --- git -------------------------------------------------------------------

if ! git --version >/dev/null 2>&1; then
    fail "git is not usable. Finish the Command Line Tools install ('xcode-select --install') and re-run."
fi
ok "git $(git --version | awk '{print $3}')"

# --- Swift toolchain -------------------------------------------------------

# If the user installed Swiftly but the env wasn't sourced in this shell, pull it in.
if [[ -f "$HOME/.swiftly/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.swiftly/env.sh"
fi

if ! command -v swift >/dev/null 2>&1; then
    fail "No Swift toolchain on PATH.

Install Swiftly (Apple's official toolchain installer), then re-run:

    curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg && \\
    installer -pkg swiftly.pkg -target CurrentUserHomeDirectory && \\
    ~/.swiftly/bin/swiftly init --quiet-shell-followup && \\
    . \"\${SWIFTLY_HOME_DIR:-\$HOME/.swiftly}/env.sh\""
fi
ok "Swift: $(swift --version 2>/dev/null | head -1)"

# --- openssl ---------------------------------------------------------------

if ! command -v openssl >/dev/null 2>&1; then
    fail "openssl not found. Reinstall Command Line Tools."
fi
ok "openssl: $(openssl version)"

# --- Claude Code credentials (warn-only) -----------------------------------

if security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1; then
    ok "Claude Code credentials present in Keychain"
else
    warn "Claude Code credentials not found in Keychain."
    warn "Install Claude Code and sign in before launching the app, otherwise"
    warn "the menubar will show '!'. https://docs.claude.com/en/docs/claude-code/overview"
fi

echo

# --- Clone -----------------------------------------------------------------

WORK_DIR="$(mktemp -d -t claude-usage-bar-install)"
trap 'rm -rf "$WORK_DIR"' EXIT

step "Cloning $REPO_URL"
git clone --depth 1 --quiet "$REPO_URL" "$WORK_DIR/src"
cd "$WORK_DIR/src"

# Confirm SwiftPM can actually parse the manifest. Broken CommandLineTools
# installs surface here with a linker error like
# `Undefined symbols: Package.__allocating_init`.
if ! swift package describe >/dev/null 2>&1; then
    fail "swift package describe failed.

Your CommandLineTools toolchain can't parse SwiftPM manifests. The fix is
to install Swiftly (a side-by-side Swift toolchain that doesn't touch your
system) and re-run:

    curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg && \\
    installer -pkg swiftly.pkg -target CurrentUserHomeDirectory && \\
    ~/.swiftly/bin/swiftly init --quiet-shell-followup && \\
    . \"\${SWIFTLY_HOME_DIR:-\$HOME/.swiftly}/env.sh\""
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
echo "  • First launch: macOS asks once for Keychain access — click 'Always Allow'."
echo "  • To update later: re-run the same install command."
