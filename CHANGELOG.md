# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-05-15

### Changed
- Dropdown polish: brand blue pixel-matched to claude.com (`#4177D0`,
  previously a brighter `#3C5BE5`); track gray bumped to 10 % opacity for
  better legibility in light mode; progress bar height 6 → 7 px.
- Refresh moved to a borderless icon button in the header next to the
  timestamp — frees the footer row, makes the dropdown feel less heavy.
- Picker, toggle, and Quit button use `.controlSize(.small)`. Quit is a
  borderless secondary with `⌘Q` shortcut. Picker auto-sizes via
  `.fixedSize()` so it doesn't sit awkwardly half-empty.

## [0.2.0] - 2026-05-15

### Added
- First-run authentication setup card in the dropdown. Walks the user
  through `claude setup-token`, accepts the resulting long-lived token
  via paste, validates format, and verifies live by triggering a refresh.
- New `TokenStore` service that owns a keychain item under the dedicated
  service name `dev.claude-usage-bar.oauth-token`, with round-trip and
  format-validation test coverage.
- 401 responses from Anthropic surface as a dedicated `unauthorized`
  error and transition the menubar to the re-auth setup card, so an
  expired/revoked token recovers in a single paste.

### Changed
- Authentication switched from reading Claude Code's `Claude Code-credentials`
  keychain entry to using a 1-year token minted by `claude setup-token`
  and stored in the app's own keychain item. The recurring "Always Allow"
  prompt — caused by Claude Code rewriting its shared entry on every OAuth
  refresh — is now structurally avoided.
- README, SECURITY, install messaging updated to reflect the
  setup-token-based flow and the new privacy guarantees.

### Removed
- `KeychainReader` and its tests. The app no longer touches the Claude
  Code-credentials keychain item.

### Migration
- Existing users will see "Setup" in the menubar on next launch and a
  setup card in the dropdown. Run `claude setup-token` once, paste the
  output, save. No further keychain prompts.

## [0.1.0] - 2026-05-13

### Added
- One-shot install script (`install.sh`) that checks every prerequisite,
  clones, builds, signs, and installs in a single curl-pipe-bash.
- Pure-logic test coverage for `ResetFormatter`, `Usage.humanOverageReason`,
  `Usage.displayPercent`, `KeychainReader.parseAccessToken`, and
  `NotificationService.decide` — 35 tests total.
- DocC comments on every service, model, and helper.
- `Services/` and `Helpers/` source folders, plus a dedicated `Helpers/Colors.swift`.

### Changed
- `NotificationService.evaluate` now delegates threshold-crossing rules to a
  pure `decide(...)` function so the logic can be unit-tested without
  touching `UserDefaults`.
- `KeychainReader.readAccessToken` now delegates JSON parsing to a pure
  `parseAccessToken(from:)` for the same reason.
- `setup-cert.sh` is idempotent (existing usable identity → no-op) and works
  with both LibreSSL (system) and OpenSSL 3 (Homebrew). The sudo
  `add-trusted-cert` step was removed — `codesign` doesn't need it.

### Removed
- Homebrew tap distribution. Ad-hoc signed binaries can't keep a stable
  Keychain "Always Allow" grant on macOS, so installs are now build-from-source.
