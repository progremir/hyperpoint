#!/bin/zsh
# Builds dist/Hyperpoint-<version>.dmg, the drag-to-Applications installer, and with --publish uploads it to a
# GitHub release, tagging the pushed HEAD v<version>.
#
# With a Developer ID identity (the default) the app and DMG are signed, notarized with the notarytool keychain
# profile $NOTARY_PROFILE and stapled, so a download opens without a Gatekeeper warning. Any other $SIGN_IDENTITY
# builds a DMG for checking the pipeline, which --publish refuses.
set -euo pipefail
cd "${0:A:h}/.."

VERSION="${1:?usage: release.sh <version> [--publish]}"
PUBLISH="${2:-}"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' ]] || { print -u2 "not a version: $VERSION"; exit 1 }

export SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Emir Amanbekov (ZZ2G9658MN)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-hyperpoint}"
NOTARIZE=0
[[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]] && NOTARIZE=1

if [[ "$PUBLISH" == --publish ]]; then
  (( NOTARIZE )) || { print -u2 "only a Developer ID build can be published: $SIGN_IDENTITY"; exit 1 }
  git diff --quiet HEAD || { print -u2 "commit or stash local changes before publishing"; exit 1 }
  [[ -n "$(git branch -r --contains HEAD)" ]] || { print -u2 "push HEAD before publishing"; exit 1 }
fi
if (( NOTARIZE )); then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null ||
    { print -u2 "no notarytool profile '$NOTARY_PROFILE': run xcrun notarytool store-credentials $NOTARY_PROFILE"; exit 1 }
fi

DIST="$PWD/dist"
DMG="$DIST/Hyperpoint-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

SIGN_TIMESTAMP=$NOTARIZE scripts/build-app.sh "$STAGE/Hyperpoint.app" "$VERSION"

VENV=.build/dmgbuild-venv
[[ -x $VENV/bin/dmgbuild ]] || { python3 -m venv $VENV && $VENV/bin/pip install --quiet dmgbuild==1.6.5 }

mkdir -p "$DIST"
rm -f "$DMG"
# hdiutil create now and then fails with "Bad file descriptor" on CI runners, so it is retried.
for attempt in 1 2 3; do
  $VENV/bin/dmgbuild -s scripts/dmg-settings.py \
    -D app="$STAGE/Hyperpoint.app" \
    -D background="$PWD/design/installer/background.tiff" \
    -D volume_icon="$PWD/design/logo/macos/AppIcon.icns" \
    Hyperpoint "$DMG" && break
  (( attempt < 3 )) || exit 1
  print -u2 "dmgbuild failed, retrying"
  sleep 5
done

# Without notarization the image stays unsigned: Gatekeeper refuses to open a downloaded DMG signed with an Apple
# Development certificate, but mounts an unsigned one.
if (( NOTARIZE )); then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi
hdiutil verify -quiet "$DMG"
(cd "$DIST" && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")
print "built $DMG"

if [[ "$PUBLISH" == --publish ]]; then
  PRERELEASE=()
  [[ "$VERSION" == *-* ]] && PRERELEASE=(--prerelease)
  gh release create "v$VERSION" "$DMG" "$DMG.sha256" --title "Hyperpoint $VERSION" --generate-notes \
    --target "$(git rev-parse HEAD)" "${PRERELEASE[@]}"
fi
