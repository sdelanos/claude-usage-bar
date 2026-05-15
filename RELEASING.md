# Releasing

How to cut a release and update the Homebrew cask.

## One-time tap repo setup

If `sdelanos/homebrew-claude-usage-bar` doesn't exist yet:

```sh
gh repo create sdelanos/homebrew-claude-usage-bar --public \
    --description "Homebrew cask for Claude Usage Bar"

git clone https://github.com/sdelanos/homebrew-claude-usage-bar.git
cd homebrew-claude-usage-bar
mkdir -p Casks
cp ../claude-usage/homebrew/Casks/claude-usage-bar.rb Casks/
git add Casks/claude-usage-bar.rb
git commit -m "Initial cask"
git push
```

The first push of the cask will have placeholder `version "0.0.0"` and a
zero sha — that's expected. The real values get filled in on the first
real release below.

## Each release

1. **Update `CHANGELOG.md`** — move entries out of `[Unreleased]` into a
   new `[X.Y.Z] - YYYY-MM-DD` section. `Info.plist`'s
   `CFBundleShortVersionString` is **not** edited by hand — `build.sh`
   stamps it from `CUBAR_VERSION` (set by the workflow from the tag).
2. **Commit + tag**:
   ```sh
   git commit -am "Release vX.Y.Z"
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main
   git push origin vX.Y.Z
   ```
3. **Wait for the Release workflow** — `.github/workflows/release.yml`
   builds the .app on `macos-26`, zips it, and attaches it to the
   GitHub release. Watch with `gh run watch` or check the Actions tab.
4. **Bump the cask**:
   ```sh
   scripts/bump-cask.sh vX.Y.Z > ../homebrew-claude-usage-bar/Casks/claude-usage-bar.rb
   ```
   The helper downloads the freshly-published `.zip`, computes its
   SHA256, and prints the updated cask formula to stdout. Pipe it
   straight into the tap repo.
5. **Commit + push the tap**:
   ```sh
   cd ../homebrew-claude-usage-bar
   git commit -am "claude-usage-bar X.Y.Z"
   git push
   ```
6. **Verify**:
   ```sh
   brew update
   brew reinstall --cask sdelanos/claude-usage-bar/claude-usage-bar
   ```

That's the whole loop. Roughly 2 minutes of human time per release,
modulo CI wait.

## Versioning

Semantic versioning, loosely:

- **Patch** — bug fix that doesn't change behavior from the user's
  point of view.
- **Minor** — new feature, new setting, new state, anything visible.
  Auth flow changes are minor (the user can recover with a single paste).
- **Major** — breaking change that requires action beyond a re-run of
  setup-token (e.g. dropping macOS 13 support, changing the keychain
  service name without auto-migration).
