# Security

## Reporting a vulnerability

Email **sebastien.delanos@akeneo.com** with the details. Please don't open
a public GitHub issue for security-relevant bugs until a fix is shipped.

I'll acknowledge within a few business days and aim to have a fix in
`main` within two weeks for anything practically exploitable.

## Threat model

Claude Usage Bar reads a single secret — a long-lived OAuth token minted
by `claude setup-token`, stored in the user's login keychain under
service `dev.claude-usage-bar.oauth-token` after a syntactic check
against the documented `sk-ant-` prefix — and sends it as a `Bearer`
header to `api.anthropic.com`. Nothing else.

The app **does not** read Claude Code's own `Claude Code-credentials`
keychain item. That entry is rotated frequently by the Claude Code CLI;
using a separate, app-owned keychain item (whose ACL we control) is what
avoids recurring "Always Allow" prompts.

In-process, the bearer is wrapped in a `SecretToken` value type whose
`description` / `debugDescription` redact to `sk-ant-***`. Callers must
explicitly call `.reveal()` to obtain the underlying string, which makes
accidental leaks (through `String(describing:)`, `os_log` default
privacy, SwiftUI debug introspection) grep-able and code-review-able.

Errors reaching the dropdown UI are pre-translated by `UserFacingError`;
no raw API response bodies (which may include `request_id` or echoed
headers) ever reach the UI or `UserDefaults`.

### What the app does not do

- Write the token (or any derivative) to disk outside the keychain
- Send the token anywhere other than `api.anthropic.com`
- Persist response bodies — only a handful of rate-limit headers are
  kept in memory and surfaced in the UI
- Open any network connection in the background other than the periodic
  `POST /v1/messages` poll (15-second per-request timeout)
- Run any code over the wire

### What persists to disk

- `~/Library/Preferences/dev.claude-usage-bar.app.plist` — the chosen
  refresh interval and the highest notification threshold already fired
  per window. No tokens, no usage history.
- The keychain item `dev.claude-usage-bar.oauth-token`, created with
  `kSecAttrAccessibleAfterFirstUnlock`. Generic-password items in the
  login keychain are not synced via iCloud Keychain (and we don't set
  `kSecAttrSynchronizable`), so the token is local to the machine.

### On uninstall

`brew uninstall --cask claude-usage-bar` runs the cask's `zap` rules,
which delete the prefs plist. **Keychain items aren't touched.** If you
want to remove the token after uninstalling, click **Sign out** in the
dropdown *first*, or, after the fact, run:

```sh
security delete-generic-password -s dev.claude-usage-bar.oauth-token
```

### Optional code-signing identity

The local code-signing identity created by `setup-cert.sh` ("ClaudeUsageBar
Dev") gives the app a stable cryptographic identity for code-signing
purposes. Since v0.2.0 it's no longer required for the auth flow — it's
just a useful default if future macOS subsystems (TCC, data-protection
keychain) start binding by signature. The cert's private key never
leaves the user's login keychain.

## Why setup-token (not direct Claude Code reuse)

`claude setup-token` is the documented way for non-interactive consumers
of a Claude subscription to authenticate. The resulting bearer is:

- **Scoped to inference only.** Cannot perform account-level operations
  (logout, billing, profile mutations) or establish Remote Control
  sessions. The minimum viable surface for our `POST /v1/messages` poll.
- **Independent of Claude Code's session.** Revoking it does not affect
  Claude Code's interactive login, and vice-versa. If Anthropic ever
  rejects it, the app surfaces the 401 in the menubar and prompts the
  user to mint a fresh one.
- **Stored only where you put it.** The CLI prints the token and exits —
  it never writes it to a shared file or keychain item.
