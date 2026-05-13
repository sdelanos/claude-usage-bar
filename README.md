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

## Install

### Option A — Drag-and-drop

1. Grab the latest `ClaudeUsageBar.zip` from
   [Releases](https://github.com/sdelanos/claude-usage-bar/releases).
2. Unzip and drag `ClaudeUsageBar.app` into `/Applications`.
3. First launch: right-click → **Open** → **Open**. (One-time Gatekeeper
   warning because the app is ad-hoc signed, not Developer-ID notarized.)

### Option B — Homebrew

```sh
brew tap sdelanos/claude-usage-bar
brew install --cask claude-usage-bar
```

The cask drops the quarantine bit on install, so no right-click dance.
The tap lives at [sdelanos/homebrew-claude-usage-bar](https://github.com/sdelanos/homebrew-claude-usage-bar).

### Option C — Build from source

See [Building](#building) below.

## Requirements

- macOS 13 (Ventura) or later
- [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) installed
  and signed in on the same Mac — the app reads its OAuth token from the
  `Claude Code-credentials` Keychain entry. If Claude Code isn't installed, the
  menu bar will show `!` and the dropdown will tell you what's missing.

The first time the app launches, macOS will ask whether to grant access to
the Keychain entry. Click **Always Allow**.

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
- Threshold notifications: every 25% on the 5h window, every 10% on the 7d
- Single ~300 KB binary, no background services, no analytics

## Privacy

- The OAuth token is read from your Keychain at every poll and put into the
  `Authorization` header. It's never written to disk and never sent anywhere
  except `api.anthropic.com`.
- The only thing the app persists locally (via `UserDefaults`) is your chosen
  refresh interval and the last notification threshold per window.
- No background telemetry, no crash reporting, no analytics.

## Building

Requires a working Swift 6 toolchain.

> **Heads-up.** If `swift build` fails with an `Undefined symbols:
> Package.__allocating_init` or `redefinition of module 'SwiftBridging'` error,
> you've hit one of the known CommandLineTools / SDK breakages in recent macOS
> releases. The fastest fix is to install [Swiftly](https://www.swift.org/install/macos/):
>
> ```sh
> curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg && \
> installer -pkg swiftly.pkg -target CurrentUserHomeDirectory && \
> ~/.swiftly/bin/swiftly init --quiet-shell-followup && \
> . "${SWIFTLY_HOME_DIR:-$HOME/.swiftly}/env.sh"
> ```
>
> Adding `source ~/.swiftly/env.sh` to your shell rc makes it permanent.

Then:

```sh
git clone https://github.com/sdelanos/claude-usage-bar.git
cd claude-usage-bar

# Optional but recommended: create a stable local code-signing identity so
# macOS doesn't re-prompt for Keychain access on every rebuild.
./setup-cert.sh

# Build + bundle .app
./build.sh

open ClaudeUsageBar.app
```

`./release.sh` produces a `dist/ClaudeUsageBar.zip` ready for upload to a
GitHub Release.

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

The Homebrew cask formula lives in its own repo at
[sdelanos/homebrew-claude-usage-bar](https://github.com/sdelanos/homebrew-claude-usage-bar);
bump the version + SHA there each time you cut a release here.

## License

MIT. See [LICENSE](LICENSE).

The bundled menu-bar icon is the Claude tray-icon template, sourced from
Anthropic's Claude desktop app. It's used here unaltered for visual continuity;
all rights belong to Anthropic.
