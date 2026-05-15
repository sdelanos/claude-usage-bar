# Claude Usage Bar

[![CI](https://github.com/sdelanos/claude-usage-bar/actions/workflows/ci.yml/badge.svg)](https://github.com/sdelanos/claude-usage-bar/actions/workflows/ci.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A tiny macOS menu-bar app that shows your Claude API rate-limit usage at a
glance. No accounts, no telemetry, no separate login — it authenticates with
a long-lived token from your existing Claude subscription.

```
☀ 24% · 41%
   │     │
   │     └── 7-day window utilization
   └──────── 5-hour session utilization
```

Click the icon to see reset times, change refresh frequency, toggle launch
at login, or quit.

## Install

```sh
brew tap sdelanos/claude-usage-bar
brew install --cask claude-usage-bar
open -a "ClaudeUsageBar"
```

That installs a prebuilt `.app` from the [GitHub releases page](https://github.com/sdelanos/claude-usage-bar/releases)
and drops it in `/Applications`. macOS may show a Gatekeeper warning on
first launch because the bundle is ad-hoc signed — the cask removes the
quarantine xattr automatically, but if you still see "unidentified
developer", right-click the app and choose **Open** once.

### First-run setup (~30 seconds)

1. Click the menu-bar icon. The dropdown shows a **Set up authentication**
   card.
2. In a Terminal, run:
   ```sh
   claude setup-token
   ```
3. Approve the OAuth flow in your browser. The CLI prints a token to the
   terminal.
4. Paste the token into the app's input field and click **Save**.

Done. The token is good for one year and is stored in a keychain item the
app owns (`dev.claude-usage-bar.oauth-token`) — no recurring keychain
prompts, no shared state with Claude Code's own credential entry.

When the token eventually expires or is revoked, the menubar shows
"Setup" again and the dropdown prompts you to re-run `claude setup-token`.

### Requirements

| What | Why | How to install |
|---|---|---|
| macOS 13+ (Ventura) | `MenuBarExtra` SwiftUI, `SMAppService` for "Launch at login" | — |
| [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) with a Pro/Max/Team/Enterprise plan | `claude setup-token` mints the long-lived token the app uses; the command requires a paid Claude subscription | Required at first-run setup, not at install |

That's it for the cask path. No Xcode, no toolchain, no signing.

## Build from source

If you'd rather not pull a prebuilt binary, the source path is one
command:

```sh
curl -fsSL https://raw.githubusercontent.com/sdelanos/claude-usage-bar/main/install.sh | bash
```

The script clones, builds, signs locally, installs to `/Applications`,
and launches. Same first-run setup as above.

Additional build-time prerequisites (the script verifies them all up
front and exits with a single combined report if anything's missing):

| What | Why | How to install |
|---|---|---|
| Xcode Command Line Tools | provides `git`, `codesign`, `security`, system `openssl` | `xcode-select --install` |
| A working Swift 6 toolchain | `swift build` to compile the app | Comes with CLT, but if `swift build` errors with `Undefined symbols: Package.__allocating_init` or `redefinition of module 'SwiftBridging'`, install [Swiftly](#toolchain) |

### Manual build

```sh
git clone https://github.com/sdelanos/claude-usage-bar.git
cd claude-usage-bar
./setup-cert.sh         # one-time, installs a stable local code-signing identity
./build.sh
mv ClaudeUsageBar.app /Applications/
open /Applications/ClaudeUsageBar.app
```

### Toolchain

If `swift build` fails with an `Undefined symbols: Package.__allocating_init`
or `redefinition of module 'SwiftBridging'` error, your CommandLineTools is
in one of the known broken states recent macOS releases ship. Quickest fix
is [Swiftly](https://www.swift.org/install/macos/):

```sh
curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg && \
installer -pkg swiftly.pkg -target CurrentUserHomeDirectory && \
~/.swiftly/bin/swiftly init --quiet-shell-followup && \
. "${SWIFTLY_HOME_DIR:-$HOME/.swiftly}/env.sh"
```

Add `source ~/.swiftly/env.sh` to your shell rc to make it permanent.

## How it works

The Anthropic API doesn't expose a dedicated usage endpoint. But every
`POST /v1/messages` response includes rate-limit headers like
`anthropic-ratelimit-unified-5h-utilization`. So the app sends the cheapest
possible request (`claude-haiku-4-5`, 1 token, body `"."`) every few minutes,
ignores the response body, and reads those headers.

A poll costs a few tokens out of your quota — negligible compared to a single
Claude Code interaction.

### Why a separate long-lived token?

Earlier versions of this app read Claude Code's short-lived OAuth access
token directly from its `Claude Code-credentials` keychain entry. That
entry gets rewritten every time Claude Code rotates its access token
(roughly hourly), which resets the item's ACL and re-triggers the
macOS "Always Allow" prompt forever.

The fix is to authenticate with a token Claude Code doesn't manage. The
documented `claude setup-token` mint flow produces a 1-year, inference-scoped
OAuth token that nothing else touches. We store it in our own keychain
item — owned by us, ACL stable — and the prompt-storm problem is structural.

## Features

- 5-hour session + 7-day window utilization, both visible in the menu bar
- Dropdown with progress bars, reset times, and human-friendly overage messages
- Configurable refresh interval (1 / 5 / 15 / 30 min)
- Launch at login (via `SMAppService`)
- Threshold notifications: every 25 % on the 5h window, every 10 % on the 7d
- Single ~300 KB binary, no background services, no analytics

## Privacy

- The long-lived token lives in a keychain item the app owns
  (`dev.claude-usage-bar.oauth-token`). It's read once per poll and put into
  the `Authorization` header. It's never written to disk outside the
  keychain and never sent anywhere except `api.anthropic.com`.
- The only thing the app persists in plain storage (via `UserDefaults`) is
  your chosen refresh interval and the last notification threshold per
  window.
- No background telemetry, no crash reporting, no analytics.

## Tests

```sh
swift test
```

Pure-logic test coverage across header parsing, token-store round-trips,
threshold-crossing decisions, reset-time formatting, and the `Usage`
helpers. SwiftUI views aren't unit-tested; manual verification is the
standard for those.

## Layout

```
Sources/ClaudeUsageBar/
  ClaudeUsageBarApp.swift              # SwiftUI scene, menu-bar label
  Models/
    Usage.swift                        # Window / RepresentativeClaim / OverageStatus
  Services/
    TokenStore.swift                   # Owns the long-lived token's keychain item
    UsageClient.swift                  # POST /v1/messages + header parser
    UsageService.swift                 # @MainActor store, refresh timer, state machine
    LaunchAtLoginService.swift         # SMAppService toggle
    NotificationService.swift          # 25 % / 10 % threshold notifications
  Views/
    MenuContentView.swift              # Dropdown UI
    SetupView.swift                    # First-run + re-auth setup card
  Helpers/
    MenuBarIcon.swift                  # Template-icon loader
    ResetFormatter.swift               # "in 32 min" / "Tue 06:00"
    Colors.swift                       # Color.claudeBlue
  Resources/
    MenuBarIcon.png                    # Template image, sourced from Claude.app

Tests/ClaudeUsageBarTests/
  UsageClientTests.swift               # header parser
  TokenStoreTests.swift                # keychain round-trips + format validation
  ResetFormatterTests.swift            # "in 32 min" vs "Tue 06:00"
  UsageHelpersTests.swift              # humanOverageReason, displayPercent
  NotificationDecisionTests.swift      # threshold-crossing rules
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — design principles, style notes,
testing expectations.

## Security

See [SECURITY.md](SECURITY.md) — threat model, what the app does and
doesn't touch, where to report a vulnerability.

## License

MIT. See [LICENSE](LICENSE).

The bundled menu-bar icon is the Claude tray-icon template, sourced from
Anthropic's Claude desktop app. It's used here unaltered for visual continuity;
all rights belong to Anthropic.
