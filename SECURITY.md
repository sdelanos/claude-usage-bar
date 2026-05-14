# Security

## Reporting a vulnerability

Email **sebastien.delanos@akeneo.com** with the details. Please don't open
a public GitHub issue for security-relevant bugs until a fix is shipped.

I'll acknowledge within a few business days and aim to have a fix in
`main` within two weeks for anything practically exploitable.

## Threat model

Claude Usage Bar reads a single secret — the OAuth access token Claude
Code stored in the user's login keychain under service
`Claude Code-credentials` — and sends it as a `Bearer` header to
`api.anthropic.com`. Nothing else.

What the app **does not** do:

- Write the token (or any derivative) to disk
- Send the token anywhere other than `api.anthropic.com`
- Persist the response bodies — only a few rate-limit headers are kept
  in memory and surfaced in the UI
- Open any network connection in the background other than the periodic
  `POST /v1/messages` poll
- Run any code over the wire — the only network reads are headers from
  the messages endpoint

What persists to disk:

- `~/Library/Preferences/dev.claude-usage-bar.app.plist` — the chosen
  refresh interval and the highest notification threshold already fired
  per window. No tokens, no usage history.

The local code-signing identity created by `setup-cert.sh` ("ClaudeUsageBar
Dev") only exists so macOS can keep an `Always Allow` Keychain ACL grant
against a stable signature. The cert's private key never leaves the
user's login keychain.
