# Claude Usage Bar

[![CI](https://github.com/sdelanos/claude-usage-bar/actions/workflows/ci.yml/badge.svg)](https://github.com/sdelanos/claude-usage-bar/actions/workflows/ci.yml)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A tiny macOS menu-bar app that shows your Claude API rate-limit usage at a
glance. No accounts, no telemetry, no separate login — it reuses the OAuth
token Claude Code already stored in your Keychain.

```
☀ 24% · 41%
   │     │
   │     └── 7-day window utilization
   └──────── 5-hour session utilization
```

Click the icon to see reset times, change refresh frequency, toggle launch
at login, or quit.

## Why build from source

The short answer: macOS's Keychain ACL only persists `Always Allow` grants
for apps with a **stable code-signing identity**. Ad-hoc signed binaries
(the kind you can hand out without an Apple Developer account) get
re-prompted for the Keychain password on every launch — even after you
click "Always Allow".

So instead of shipping a pre-built `.app`, this repo gives you a 30-second
one-time setup that creates a local self-signed identity on your machine.
After that, the Keychain prompt happens exactly once.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/sdelanos/claude-usage-bar/main/install.sh | bash
```

That's it. The script:

1. Checks you're on macOS 13+ with a working Swift toolchain.
2. Clones this repo into a temp directory.
3. Installs (once) a local code-signing identity in your login keychain.
4. Builds `ClaudeUsageBar.app`, signed with that identity.
5. Moves it to `/Applications` and launches it.

First launch: macOS asks once for Keychain access — click **Always Allow**.
You'll never see the prompt again. To update later, re-run the same command.

### Want to inspect first?

Reasonable. The script is short and lives at
[`install.sh`](install.sh). Read it, then run it locally with:

```sh
curl -fsSL https://raw.githubusercontent.com/sdelanos/claude-usage-bar/main/install.sh > install.sh
less install.sh
bash install.sh
```

### Requirements

The install script verifies every one of these before doing anything, and
exits with a clear error if any is missing.

| What | Why | How to install |
|---|---|---|
| macOS 13+ (Ventura) | `MenuBarExtra` SwiftUI, `SMAppService` for "Launch at login" | — |
| Xcode Command Line Tools | provides `git`, `codesign`, `security`, system `openssl` | `xcode-select --install` |
| A working Swift 6 toolchain | `swift build` to compile the app | Comes with CLT, but if `swift build` errors with `Undefined symbols: Package.__allocating_init` or `redefinition of module 'SwiftBridging'`, install Swiftly (see [toolchain](#toolchain)) |
| [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) installed & signed in | the app reads its OAuth token from the `Claude Code-credentials` Keychain entry | Required at runtime, not build time — the installer just warns if it's missing |

Nothing else. No Xcode.app, no Apple Developer account, no Homebrew.

### Manual install

If you'd rather not pipe a script:

```sh
git clone https://github.com/sdelanos/claude-usage-bar.git
cd claude-usage-bar
./setup-cert.sh
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

## Features

- 5-hour session + 7-day window utilization, both visible in the menu bar
- Dropdown with progress bars, reset times, and human-friendly overage messages
- Configurable refresh interval (1 / 5 / 15 / 30 min)
- Launch at login (via `SMAppService`)
- Threshold notifications: every 25 % on the 5h window, every 10 % on the 7d
- Single ~300 KB binary, no background services, no analytics

## Privacy

- The OAuth token is read from your Keychain at every poll and put into the
  `Authorization` header. It's never written to disk and never sent anywhere
  except `api.anthropic.com`.
- The only thing the app persists locally (via `UserDefaults`) is your chosen
  refresh interval and the last notification threshold per window.
- No background telemetry, no crash reporting, no analytics.

## Tests

```sh
swift test
```

35 tests across six suites covering every piece of pure logic — header
parsing, JSON token extraction, threshold-crossing decisions, reset-time
formatting, and the `Usage` helpers. SwiftUI views aren't unit-tested;
manual verification is the standard for those.

## Layout

```
Sources/ClaudeUsageBar/
  ClaudeUsageBarApp.swift              # SwiftUI scene, menu-bar label
  Models/
    Usage.swift                        # Window / RepresentativeClaim / OverageStatus
  Services/
    KeychainReader.swift               # Reads the Claude Code OAuth token
    UsageClient.swift                  # POST /v1/messages + header parser
    UsageService.swift                 # @MainActor store, refresh timer, state machine
    LaunchAtLoginService.swift         # SMAppService toggle
    NotificationService.swift          # 25 % / 10 % threshold notifications
  Views/
    MenuContentView.swift              # Dropdown UI
  Helpers/
    MenuBarIcon.swift                  # Template-icon loader
    ResetFormatter.swift               # "in 32 min" / "Tue 06:00"
    Colors.swift                       # Color.claudeBlue
  Resources/
    MenuBarIcon.png                    # Template image, sourced from Claude.app

Tests/ClaudeUsageBarTests/
  UsageClientTests.swift               # header parser
  KeychainReaderTests.swift            # JSON token extraction
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
