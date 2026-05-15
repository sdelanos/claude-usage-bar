# Contributing

Thanks for your interest. This is a small, focused project — the most
useful contributions are bug reports with reproducible steps, and small
PRs that match the existing style.

## Quick start

```sh
git clone https://github.com/sdelanos/claude-usage-bar.git
cd claude-usage-bar
./setup-cert.sh    # one-time
swift test         # runs in well under a second
./build.sh         # produces ClaudeUsageBar.app
open ClaudeUsageBar.app
```

If `swift test` or `swift build` fails with `Undefined symbols:
Package.__allocating_init` or `redefinition of module 'SwiftBridging'`,
your CommandLineTools toolchain is in one of the known broken states.
The fix is documented in the [README's toolchain section](README.md#toolchain).

## Code style

- **Comments**: write **why**, not **what**. If a future reader can deduce
  what the line does from the line itself, the comment is noise. If a
  comment doesn't survive a reasonable refactor (mentions specific
  callers, the current task, or a closed PR), it's noise too. Prefer
  zero comments to filler comments.
- **Public surface**: every type/function exposed to other files gets a
  `///` doc comment. Internal helpers don't.
- **Errors**: surface them as typed Swift errors with a
  `CustomStringConvertible` description so the menu-bar dropdown can show
  the user something actionable.
- **Side effects out, pure logic in**: anything threshold-like, parsing,
  or stateful gets factored into a pure function the tests cover. The
  side-effecting wrapper stays tiny.
- **Strings the user sees** are English. The app is not localized; if
  that changes we'll move strings to a `.strings` file then.

## Testing

- New pure logic comes with tests. We use Apple's
  [swift-testing](https://github.com/apple/swift-testing) framework
  (`import Testing`, `@Test`, `#expect`).
- I/O (keychain, URLSession) is behind protocols (`TokenStoring`,
  `UsageFetching`) so the state machine in `UsageService` is testable
  with `InMemoryTokenStore` + a mock fetcher — never touches the real
  keychain or the network.
- The `UsageClient.fetch` integration tests use `URLProtocol` stubs;
  serialized via `@Suite(.serialized)` because the protocol's handler is
  global.
- SwiftUI views are not unit-tested. Snapshot tests aren't worth their
  maintenance for a single-dropdown UI; manual verification is fine.
- `Tests/ClaudeUsageBarTests/` mirrors `Sources/ClaudeUsageBar/`
  one-for-one where it makes sense.

## Architecture in one paragraph

`ClaudeUsageBarApp` composes `UsageService` + `LaunchAtLoginService` and
injects them into `MenuContentView`. `UsageService` reads a token from
`TokenStoring`, hands it to `UsageFetching`, then forwards the resulting
`Usage` to `NotificationService.evaluate` — and publishes a `State` enum
the views observe (`.loading`, `.loaded`, `.needsSetup`, `.error`). The
poll loop is a structured `Task` cancelled on sign-out / interval change.
Every error reachable from the UI goes through `UserFacingError.translate`
so raw `URLError` / response-body bytes never reach the dropdown.
Tokens are wrapped in `SecretToken` and never printed.

## Reporting bugs

Open an issue with the bug template. The most useful debugging info is:

- macOS version (`sw_vers -productVersion`)
- Swift toolchain (`swift --version`)
- The exact symptom in the menu bar (`%`, `!`, `…`)
- Output of `./build.sh` if you built from source
