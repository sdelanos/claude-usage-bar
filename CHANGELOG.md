# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-05-15

### Added
- `SecretToken` wrapper type: refuses to print itself (description /
  debugDescription redact to `sk-ant-***`). Callers explicitly call
  `.reveal()` so accidental leaks via `String(describing:)`, `os_log`
  default privacy, or SwiftUI debug introspection become grep-able.
- `UserFacingError` translator: a single chokepoint between thrown
  errors and the dropdown UI. Maps `URLError`, `UsageClientError`, and
  `TokenStoreError` to short, actionable messages. Unknown error types
  fire `assertionFailure` in DEBUG.
- `TokenStoring` / `UsageFetching` protocols with `InMemoryTokenStore`
  and `MockUsageFetcher` for tests — `UsageService` is now fully testable
  without ever touching the keychain or the network.
- "Sign out" button in the dropdown (was dead-coded). Visible when
  authenticated and not in setup.
- "Manual only" refresh option in the picker (interval = 0 skips the
  poll loop entirely).
- Open-Login-Items-Settings deep link in the launch-at-login row when
  macOS reports `.requiresApproval`.
- `os.Logger` instrumentation in every service so the menubar is
  debuggable from Console.app.
- New tests: state-machine coverage for `UsageService`, URLProtocol-stubbed
  integration tests for `UsageClient.fetch` (200 / 401 / 500 paths),
  `SecretToken` + `UserFacingError` redaction guarantees, length-boundary
  cases on `TokenFormat.looksValid`. 60 tests total, sub-second.

### Changed
- Swift 6 strict concurrency mode (`.swiftLanguageMode(.v6)`) enabled
  for both targets. `UsageService` is `@MainActor`, `NotificationService`
  pinned to `@MainActor`, the poll loop is now a structured `Task`
  cancelled on sign-out / interval change (was a `Timer` whose closure
  captured `[weak self]` in a way Swift 6 wouldn't accept).
- `UsageClient.fetch` takes a `SecretToken` instead of a raw `String`;
  describes errors without leaking the response body; sets a 15-second
  per-request timeout (default URLSession is 60); sends a versioned
  `User-Agent` so Anthropic can identify the polling client.
- `UsageClient.parse` no longer force-unwraps after the missing-headers
  guard. Static endpoint URL falls back to a sentinel + `assertionFailure`
  instead of `!`.
- Menu-bar label uses SF Symbols for the `needsSetup` and `error` states
  (gearshape, exclamationmark.triangle) instead of "Setup" / "!" text.
- Error UI exposes a Retry button when the underlying error is retryable.
- `UsageRow` / `CapsuleBar` / `OverageBanner` conform to `Equatable` so
  SwiftUI diffs cheaply.
- `CFBundleShortVersionString` is now stamped at build time by `build.sh`
  from `CUBAR_VERSION` (set by CI from the release tag), so the in-bundle
  version stays in lockstep with the cask.
- `Info.plist` gains `LSApplicationCategoryType = developer-tools` and a
  proper `NSHumanReadableCopyright`.
- CI runs on both macos-15 and macos-26 with code-coverage export, a
  separate `swift build -c release` job, and a `swiftformat --lint` job.
  Dependabot enabled for github-actions.
- `install.sh` accepts `CUBAR_REF=<tag>` to pin the install; captures
  setup-cert + build output to logfiles and tails the last 50 lines on
  failure instead of swallowing them.
- `setup-cert.sh` uses a per-run random password for the in-flight .p12
  instead of a hardcoded "tmp".

### Removed
- Dead model fields: `Usage.Window.status`, `Usage.RepresentativeClaim`,
  `Usage.displayPercent`. The dropdown shows both windows directly; the
  parser now only extracts what we use.
- Force-unwraps in source.
- The `description` of `UsageClientError.httpError` no longer surfaces
  the raw response body (kept in `debugBody` for `Logger` only).

### Fixed
- The "stored interval" boot path now distinguishes "user picked manual
  only" from "key never set" — was conflating both into the default.
- `LaunchAtLoginService.setEnabled` errors are translated into actionable
  messages (e.g. `.requiresApproval` → "Enable Claude Usage Bar in
  System Settings → General → Login Items.").
- Threshold notifications use deterministic identifiers
  (`threshold.<window>.<percent>`) so macOS de-duplicates duplicates;
  also gated on the cached authorization grant so we don't fire
  `add(_:)` 200 times a day for a silent permission.

## [0.2.2] - 2026-05-15

### Changed
- CI release runner bumped from `macos-15` to `macos-26`. The shipped
  binary now embeds an SDK-26 build version, so AppKit serves the
  Tahoe-era SwiftUI styling instead of the macOS-15-era look. Without
  this, `.controlSize(.small)` and friends rendered chunkier on macOS 26
  than on the developer's local build — same source, different SDK
  target. CI workflow follows the same bump.

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
