#!/bin/sh
# Publishes the Homebrew cask for the current VERSION to github.com/aubinvan/homebrew-tap.
# Run after the GitHub release is published (needs `gh` auth with write access to the tap).
# Usage: ./scripts/update-cask.sh
set -eu
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
TAP="aubinvan/homebrew-tap"
CASK_PATH="Casks/purevalet.rb"
BASE="https://github.com/aubinvan/purevalet/releases/download/v${VERSION}/PureValet-${VERSION}.dmg"

# Use the published checksum, and check that the published DMG really matches it.
SHA256="$(curl -fsSL "${BASE}.sha256" | cut -d' ' -f1)"
[ "${#SHA256}" = 64 ] || { echo "No published SHA-256 for ${VERSION} (is the release out?)." >&2; exit 1; }
REMOTE_SHA="$(curl -fsSL "$BASE" | shasum -a 256 | cut -d' ' -f1)"
[ "$REMOTE_SHA" = "$SHA256" ] || { echo "Published DMG does not match its published SHA-256." >&2; exit 1; }

CASK="$(mktemp)"
trap 'rm -f "$CASK"' EXIT
cat > "$CASK" <<CASK
cask "purevalet" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/aubinvan/purevalet/releases/download/v#{version}/PureValet-#{version}.dmg"
  name "PureValet"
  desc "Menu bar app to run and control Laravel Valet"
  homepage "https://github.com/aubinvan/purevalet"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "PureValet.app"

  zap trash: "~/Library/Preferences/dev.aubin.purevalet.plist"

  caveats <<~EOS
    PureValet is not notarized. If macOS blocks the first launch, run:
      xattr -dr com.apple.quarantine "#{appdir}/PureValet.app"
  EOS
end
CASK
ruby -c "$CASK" >/dev/null

CURRENT_SHA="$(gh api "repos/${TAP}/contents/${CASK_PATH}" -q .sha 2>/dev/null || true)"
if [ -n "$CURRENT_SHA" ]; then
    gh api -X PUT "repos/${TAP}/contents/${CASK_PATH}" -f message="purevalet ${VERSION}" -f content="$(base64 < "$CASK")" -f sha="$CURRENT_SHA" >/dev/null
else
    gh api -X PUT "repos/${TAP}/contents/${CASK_PATH}" -f message="purevalet ${VERSION}" -f content="$(base64 < "$CASK")" >/dev/null
fi
echo "OK: ${TAP}/${CASK_PATH} → ${VERSION}"
