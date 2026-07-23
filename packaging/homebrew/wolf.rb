class Wolf < Formula
  desc "Self-binding website blocker for macOS — a commitment device, not a filter"
  homepage "https://installwolf.com"
  license "MIT"

  # Installable today without a release:  brew install --HEAD installwolf/tap/wolf
  head "https://github.com/installwolf/wolf.git", branch: "main"

  # Stable release: bump `url` + `sha256` on every tag. See README.md in this dir
  # for the one-command release flow that prints the sha256 to paste here.
  url "https://github.com/installwolf/wolf/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "2f47851b15785fb1dd83ad569633c4f84e4350bf399608c620cd7a998c35fcba"

  depends_on :macos
  depends_on xcode: :build

  def install
    # --disable-sandbox: SwiftPM's build sandbox conflicts with Homebrew's.
    system "swift", "build", "--disable-sandbox", "-c", "release"
    # Keep wolf + wolfd side-by-side in libexec so `wolf bootstrap` can find the
    # daemon binary as a sibling; expose only the CLI on PATH.
    libexec.install ".build/release/wolf", ".build/release/wolfd"
    bin.install_symlink libexec/"wolf"
  end

  def caveats
    <<~EOS
      wolf (CLI) is installed, but nothing is enforced yet. One privileged step
      installs the root watchdog, wires the pf anchor, and starts blocking:

          sudo wolf bootstrap

      Then have your accountability partner set the passphrase (so you never
      learn it) and block your first sites:

          sudo wolf set-passphrase
          wolf add pornhub.com xvideos.com

      Everyday commands need no sudo — the root daemon enforces the removal gate.
      Break-glass escape hatch (wipes the setup, always works, is audit-logged):

          sudo wolf panic

      Upgrading later? Re-run `sudo wolf bootstrap` after `brew upgrade` to point
      the watchdog at the new binary.
    EOS
  end

  test do
    # status is read-only and needs no root; point it at a throwaway home.
    ENV["WOLF_HOME"] = testpath/"home"
    assert_match "blocked", shell_output("#{bin}/wolf status")
  end
end
