cask "claude-usage-bar" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/sdelanos/claude-usage-bar/releases/download/v#{version}/ClaudeUsageBar-#{version}.zip"
  name "Claude Usage Bar"
  desc "Menu-bar app showing live Claude API rate-limit usage"
  homepage "https://github.com/sdelanos/claude-usage-bar"

  depends_on macos: ">= :ventura"

  app "ClaudeUsageBar.app"

  # The release artifact is ad-hoc signed (no Developer ID). macOS adds the
  # quarantine xattr on download; users see the Gatekeeper "unidentified
  # developer" prompt on first launch. Stripping the xattr at install time
  # smooths over that one-off — the user already trusts Homebrew enough to
  # have run `brew install`, so dropping the same alarm a second time adds
  # no protection.
  postflight do
    system_command "/usr/bin/xattr",
                   args:         ["-cr", "#{appdir}/ClaudeUsageBar.app"],
                   sudo:         false,
                   must_succeed: false
  end

  uninstall quit: "dev.claude-usage-bar.app"

  zap trash: [
    "~/Library/Preferences/dev.claude-usage-bar.app.plist",
  ]

  caveats <<~EOS
    On first launch, click the menu-bar icon and follow the setup card:

      1. In Terminal:   claude setup-token
      2. Approve in your browser
      3. Paste the printed token into the app and Save

    The token is good for one year. When it expires, the dropdown will
    prompt you to re-run setup-token.
  EOS
end
