# Claude Usage Bar

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

### Requirements

- macOS 13 (Ventura) or later
- [Claude Code](https://docs.claude.com/en/docs/claude-code/overview)
  installed and signed in — the app reads its OAuth token from the
  `Claude Code-credentials` Keychain entry
- A working Swift 6 toolchain (see [the toolchain note](#toolchain) below
  if `swift build` fails)

### Steps

```sh
git clone https://github.com/sdelanos/claude-usage-bar.git
cd claude-usage-bar

# One-time: generate a local code-signing identity ("ClaudeUsageBar Dev")
# so macOS will remember the Keychain "Always Allow" decision.
./setup-cert.sh

# Build the .app and sign it with the identity above.
./build.sh

# Move it to /Applications (so "Launch at login" survives a reboot).
mv ClaudeUsageBar.app /Applications/

open /Applications/ClaudeUsageBar.app
```

First launch: macOS asks once for Keychain access — click **Always Allow**.
You'll never see the prompt again.

### Updating

```sh
cd claude-usage-bar
git pull
killall ClaudeUsageBar
./build.sh
rm -rf /Applications/ClaudeUsageBar.app
mv ClaudeUsageBar.app /Applications/
open /Applications/ClaudeUsageBar.app
```

The code-signing identity from `setup-cert.sh` is reused across builds, so
the Keychain grant stays valid.

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

The test suite covers the rate-limit-header parser, which is the only
non-trivial piece of pure logic in the codebase.

## Layout

```
Sources/ClaudeUsageBar/
  ClaudeUsageBarApp.swift     # SwiftUI scene, menu-bar label
  KeychainReader.swift        # Reads the Claude Code OAuth token
  UsageClient.swift           # POST /v1/messages + header parser
  UsageService.swift          # @MainActor store, refresh timer, state machine
  LaunchAtLoginService.swift  # SMAppService toggle
  NotificationService.swift   # 25 % / 10 % threshold notifications
  MenuBarIcon.swift           # Template-icon loader
  ResetFormatter.swift        # "in 32 min" / "Tue 06:00"
  Models/Usage.swift          # Usage / Window / RepresentativeClaim / OverageStatus
  Views/MenuContentView.swift # Dropdown UI
  Resources/MenuBarIcon.png   # Template image, sourced from Claude.app
Tests/ClaudeUsageBarTests/
  UsageClientTests.swift      # swift-testing suite (4 cases)
```

## License

MIT. See [LICENSE](LICENSE).

The bundled menu-bar icon is the Claude tray-icon template, sourced from
Anthropic's Claude desktop app. It's used here unaltered for visual continuity;
all rights belong to Anthropic.
