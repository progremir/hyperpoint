#!/bin/zsh
# Builds dist/Hyperpoint-<version>.dmg, the drag-to-Applications installer, and with --publish uploads it to a
# GitHub release, tagging the pushed HEAD v<version>. The app is signed by build-app.sh with $SIGN_IDENTITY.
set -euo pipefail
cd "${0:A:h}/.."

VERSION="${1:?usage: release.sh <version> [--publish]}"
PUBLISH="${2:-}"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' ]] || { print -u2 "not a version: $VERSION"; exit 1 }

if [[ "$PUBLISH" == --publish ]]; then
  git diff --quiet HEAD || { print -u2 "commit or stash local changes before publishing"; exit 1 }
  [[ -n "$(git branch -r --contains HEAD)" ]] || { print -u2 "push HEAD before publishing"; exit 1 }
fi

DIST="$PWD/dist"
DMG="$DIST/Hyperpoint-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

scripts/build-app.sh "$STAGE/Hyperpoint.app" "$VERSION"

VENV=.build/dmgbuild-venv
[[ -x $VENV/bin/dmgbuild ]] || { python3 -m venv $VENV && $VENV/bin/pip install --quiet dmgbuild==1.6.5 }

mkdir -p "$DIST"
rm -f "$DMG"
$VENV/bin/dmgbuild -s scripts/dmg-settings.py \
  -D app="$STAGE/Hyperpoint.app" \
  -D background="$PWD/design/installer/background.tiff" \
  -D volume_icon="$PWD/design/logo/macos/AppIcon.icns" \
  Hyperpoint "$DMG"
# The image stays unsigned. Gatekeeper refuses to open a downloaded DMG signed with an Apple Development certificate,
# but mounts an unsigned one and shows the installer window. The app inside carries the signature.
hdiutil verify -quiet "$DMG"
(cd "$DIST" && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")
print "built $DMG"

if [[ "$PUBLISH" == --publish ]]; then
  PRERELEASE=()
  [[ "$VERSION" == *-* ]] && PRERELEASE=(--prerelease)
  gh release create "v$VERSION" "$DMG" "$DMG.sha256" --title "Hyperpoint $VERSION" --generate-notes \
    --target "$(git rev-parse HEAD)" "${PRERELEASE[@]}"
fi
