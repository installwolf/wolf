# Publishing Wolf on Homebrew

Wolf ships through a **personal tap** — the public repo `installwolf/homebrew-tap`.
A tap has none of homebrew-core's restrictions, so we can install a real root
LaunchDaemon (via `sudo wolf bootstrap`), which homebrew-core would reject as
"too hard to uninstall" — exactly the property a commitment device needs.
`wolf.rb` in this directory is the source of truth; publishing means copying it
into `installwolf/homebrew-tap/Formula/wolf.rb`.

## What the user runs

```bash
# Once a release is tagged:
brew install installwolf/tap/wolf

# Available right now, straight from main (no release needed):
brew install --HEAD installwolf/tap/wolf

# Then the single privileged setup step:
sudo wolf bootstrap
```

`brew install installwolf/tap/wolf` auto-taps `github.com/installwolf/homebrew-tap`;
no separate `brew tap` needed.

## Keeping the tap in sync

The formula lives in two places: this dir (source of truth) and the tap repo.
After editing `packaging/homebrew/wolf.rb` here, copy it over and push:

```bash
brew tap installwolf/tap                                   # clone the tap locally (once)
cp packaging/homebrew/wolf.rb "$(brew --repository installwolf/tap)/Formula/wolf.rb"
git -C "$(brew --repository installwolf/tap)" commit -am "Update wolf formula" && \
git -C "$(brew --repository installwolf/tap)" push
```

## Cutting a stable release (fills in url + sha256)

`--HEAD` is fine for early testers, but a tagged release is what most people get.
Each release, bump `url`/`sha256` in the tap's `Formula/wolf.rb`:

```bash
# 1. Tag and push from the wolf repo.
cd ~/Code/wolf
git tag v0.1.0 && git push origin v0.1.0

# 2. Get the tarball sha256 (paste this into the formula's `sha256`).
curl -sL https://github.com/installwolf/wolf/archive/refs/tags/v0.1.0.tar.gz \
  | shasum -a 256

# 3. In the tap's Formula/wolf.rb, set `url` to the v0.1.0 tarball and `sha256`
#    to the value above, then commit + push.
```

## Verifying the formula before publishing

```bash
brew install --build-from-source ./packaging/homebrew/wolf.rb   # local file install
brew test wolf
brew audit --new --formula wolf                                 # style/policy check
```

## Notes / gotchas (from the ecosystem)

- Every other blocker on Homebrew (SelfControl, Cold Turkey, Freedom, Focus) is a
  **cask** — a prebuilt `.app`. Wolf is the first daemon-enforced *formula* blocker,
  and the porn-specific niche is empty. That novelty is a positioning point, but it
  also means we can't lean on a cask template — the formula is hand-rolled.
- The menu-bar app (`WolfBar`) deliberately stays **out** of this formula. Formulae
  are for CLI binaries; a `.app` bundle belongs in a separate cask later. v1 is
  CLI-first — the `wolf` CLI is the complete tool.
- `swift build` needs `--disable-sandbox` under Homebrew.
- The daemon binary is copied to a **root-owned** path by `wolf bootstrap`, never run
  from the user-writable Homebrew prefix — otherwise the user (the adversary in our
  threat model) could swap `wolfd` for a no-op.
