# Claude Usage Bar

[![CI](https://github.com/sdelanos/claude-usage-bar/actions/workflows/ci.yml/badge.svg)](https://github.com/sdelanos/claude-usage-bar/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/sdelanos/claude-usage-bar?sort=semver)](https://github.com/sdelanos/claude-usage-bar/releases)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A tiny macOS menu-bar app that shows your Claude API rate-limit usage at a
glance. No accounts, no telemetry, no separate login — it authenticates with
a long-lived token from your existing Claude subscription.

<p align="center">
  <img src="docs/screenshots/dropdown.png" alt="Claude Usage Bar dropdown" width="360" />
</p>

```
☀ 24% · 41%
   │     │
   │     └── 7-day window utilization
   └──────── 5-hour session utilization
```

Click the icon to see reset times, change refresh frequency, toggle launch
at login, sign out, or quit.

## Install

```sh
brew tap sdelanos/claude-usage-bar
brew install --cask claude-usage-bar
open -a "ClaudeUsageBar"
```

That installs a prebuilt `.app` from the [GitHub releases page](https://github.com/sdelanos/claude-usage-bar/releases)
and drops it in `/Applications`. The cask strips the quarantine xattr
automatically. If macOS still shows the "unidentified developer" Gatekeeper
prompt on first launch, right-click the app and choose **Open** once.

### First-run setup (~30 seconds)

1. Click the menu-bar icon. The dropdown shows a **Set up authentication** card.
2. In a Terminal, run:
   ```sh
   claude setup-token
   ```
3. Approve the OAuth flow in your browser. The CLI prints a token to the terminal.
4. Paste the token into the app's input field and click **Save**.

Done. The token is good for one year and lives in a keychain item the app
owns (`dev.claude-usage-bar.oauth-token`). No recurring keychain prompts,
no shared state with Claude Code's own credential entry — see [Design
notes](#design-notes) for why that matters.

When the token expires or is revoked, the menubar shows "Setup" again
and the dropdown prompts you to re-run `claude setup-token`.

### Requirements

| What | Why | How to install |
|---|---|---|
| macOS 13+ (Ventura) | `MenuBarExtra` SwiftUI, `SMAppService` for "Launch at login" | — |
| [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) with a Pro/Max/Team/Enterprise plan | `claude setup-token` mints the long-lived token the app uses; the command requires a paid Claude subscription | Required at first-run setup, not at install |

That's it. No Xcode, no toolchain, no signing.

## Design notes

The interesting engineering decision in the codebase is **why this app
authenticates with `claude setup-token` instead of reading Claude Code's
own keychain entry**.

Earlier versions did the latter. macOS would prompt for keychain access
once on first launch, the user would click "Always Allow," and that was
supposed to be it. Except: Claude Code rewrites its `Claude Code-credentials`
keychain entry every time its OAuth access token rotates (~hourly). Each
rewrite resets the item's ACL, which means the next time the menubar app
polls, the user is prompted again. Every hour. Forever.

The fix is structural: don't depend on a shared keychain item the consumer
doesn't own. `claude setup-token` is the documented Anthropic flow for
unattended consumers of a Claude subscription; it mints a 1-year,
inference-scoped bearer that lives wherever you put it. The menubar app
puts it in a keychain item it owns — ACL is set once, nothing else writes
to it, no recurring prompts.

Full security threat model in [SECURITY.md](SECURITY.md).

## Build from source

If you'd rather not pull a prebuilt binary, the source path is one command:

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
`anthropic-ratelimit-unified-5h-utilization`. So the app sends the
cheapest possible request (`claude-haiku-4-5`, `max_tokens: 1`, body
`"."`) every few minutes, ignores the response body, and reads those
headers.

A poll costs a few tokens out of your quota — negligible compared to a
single Claude Code interaction.

## Features

- 5-hour session + 7-day window utilization, both visible in the menu bar
- Dropdown with progress bars, reset times, and human-friendly overage messages
- Configurable refresh interval (manual / 1 / 5 / 15 / 30 min)
- Sign out + re-auth flow when the token expires
- Launch at login (via `SMAppService`)
- Threshold notifications: every 25 % on the 5h window, every 10 % on the 7d
- Single ad-hoc-signed `.app`, no background services, no analytics

## Privacy

- The long-lived token lives in a keychain item the app owns
  (`dev.claude-usage-bar.oauth-token`). Read once per poll into the
  `Authorization: Bearer` header. Never written to disk outside the keychain,
  never sent anywhere except `api.anthropic.com`.
- The in-process token wrapper (`SecretToken`) refuses to print itself —
  no accidental leak through `String(describing:)`, debug descriptions,
  or `os_log`'s default privacy.
- Plain-storage persistence (via `UserDefaults`): your chosen refresh
  interval and the highest notification threshold already fired per
  window. No tokens, no usage history.
- No background telemetry, no crash reporting, no analytics.

## Tests

```sh
swift test
```

60 tests across the parser, the state machine, the token store, the
threshold-crossing decision logic, error translation, and the secret-token
redaction guarantees. SwiftUI views aren't unit-tested.

CI runs the suite on both macOS 15 and macOS 26 with code coverage, plus
a separate release-config build job to catch dead-code-elimination edge
cases, plus a SwiftFormat lint job. Detail: [.github/workflows/ci.yml](.github/workflows/ci.yml).

## Layout

```
Sources/ClaudeUsageBar/
  ClaudeUsageBarApp.swift              # SwiftUI scene, menu-bar label
  Models/
    Usage.swift                        # Window / OverageStatus
  Services/
    TokenStore.swift                   # TokenStoring protocol + Keychain & InMemory impls
    UsageClient.swift                  # UsageFetching protocol + URLSession-backed client
    UsageService.swift                 # @MainActor store, structured-Task poll, state machine
    LaunchAtLoginService.swift         # SMAppService + login-items deep link
    NotificationService.swift          # 25 % / 10 % threshold notifications
  Views/
    MenuContentView.swift              # Dropdown UI
    SetupView.swift                    # First-run + re-auth setup card
  Helpers/
    SecretToken.swift                  # Un-loggable bearer wrapper
    UserFacingError.swift              # Single point of error → message translation
    MenuBarIcon.swift                  # Template-icon loader
    ResetFormatter.swift               # "in 32 min" / "Tue 06:00"
    Colors.swift                       # Color.claudeBlue, claudeTrack, claudeWarn*
  Resources/
    MenuBarIcon.png                    # Template image, sourced from Claude.app

Tests/ClaudeUsageBarTests/
  UsageClientTests.swift               # header parser + URLProtocol-stubbed fetch
  UsageServiceTests.swift              # state-machine coverage with mocks
  UsageHelpersTests.swift              # humanOverageReason
  UserFacingErrorTests.swift           # error translator + SecretToken redaction
  TokenStoreTests.swift                # format validator + Keychain & InMemory round-trips
  NotificationDecisionTests.swift      # threshold-crossing rules
  ResetFormatterTests.swift            # "in 32 min" vs "Tue 06:00"
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
Anthropic's Claude desktop app. It's used here unaltered for visual
continuity; all rights belong to Anthropic.
