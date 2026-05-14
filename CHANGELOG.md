# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
