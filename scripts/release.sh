#!/bin/zsh
# Builds dist/Hyperpoint-<version>.dmg, the drag-to-Applications installer, and with --publish uploads it to a
# GitHub release, tagging the pushed HEAD v<version>, and to the hyperpoint-releases R2 bucket, which the site serves
# at /download to anyone, with or without access to the repository. It also adds the release to the Sparkle appcast
# the site serves at /appcast.xml, which installed copies read to update themselves. A prerelease goes on the appcast's
# beta channel, which only copies with "Include beta versions" on can see.
#
# Optional, for --publish: NOTES=<file.md> shows that markdown as the release notes in the update window, and
# ROLLOUT_INTERVAL=<seconds> makes Sparkle offer the update to one of seven groups of users every interval (86400 takes
# a week); a user who checks by hand gets it at once. The appcast is signed with the EdDSA key in the login keychain,
# which `generate_keys` made; the first release asks to let generate_appcast use it.
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
NOTES="${NOTES:-}"
SITE=https://hyperpoint.progremir.dev
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
NOTARIZE=0
[[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]] && NOTARIZE=1

if [[ "$PUBLISH" == --publish ]]; then
  (( NOTARIZE )) || { print -u2 "only a Developer ID build can be published: $SIGN_IDENTITY"; exit 1 }
  git diff --quiet HEAD || { print -u2 "commit or stash local changes before publishing"; exit 1 }
  [[ -n "$(git branch -r --contains HEAD)" ]] || { print -u2 "push HEAD before publishing"; exit 1 }
  [[ -x site/node_modules/.bin/cf ]] || { print -u2 "run npm ci in site/ before publishing"; exit 1 }
  (cd site && node_modules/.bin/cf r2 objects get latest --bucket-name hyperpoint-releases --text >/dev/null) ||
    { print -u2 "cannot read the hyperpoint-releases bucket: run npx cf auth login in site/"; exit 1 }
  [[ -z "$NOTES" || -f "$NOTES" ]] || { print -u2 "no release notes at $NOTES"; exit 1 }
  swift package resolve
  $SPARKLE_BIN/generate_keys -p >/dev/null ||
    { print -u2 "no Sparkle signing key in the keychain: import the backup with $SPARKLE_BIN/generate_keys -f <file>"; exit 1 }
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
# hdiutil create now and then fails with "Bad file descriptor" (seen on GitHub's macOS runners), so it is retried.
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
  r2get() { (cd site && node_modules/.bin/cf r2 objects get "$1" --bucket-name hyperpoint-releases) }
  r2put() { (cd site && node_modules/.bin/cf r2 objects put "$1" --bucket-name hyperpoint-releases "${@:2}" >/dev/null) }

  # The appcast is rebuilt from the published one, so the releases already in it stay listed beside this one. It is
  # made before anything is published, so a signing failure publishes nothing.
  FEED="$STAGE/feed"
  mkdir -p "$FEED"
  if ! r2get appcast.xml > "$FEED/appcast.xml" 2> "$STAGE/appcast.err"; then
    grep -q "does not exist" "$STAGE/appcast.err" || { cat "$STAGE/appcast.err" >&2; exit 1 }
    rm "$FEED/appcast.xml"
  fi
  cp "$DMG" "$FEED/"
  [[ -n "$NOTES" ]] && cp "$NOTES" "$FEED/${DMG:t:r}.md"
  APPCAST=()
  (( ${#PRERELEASE} )) && APPCAST+=(--channel beta)
  [[ -n "${ROLLOUT_INTERVAL:-}" ]] && APPCAST+=(--phased-rollout-interval "$ROLLOUT_INTERVAL")
  # The site serves only DMGs, so no delta updates.
  $SPARKLE_BIN/generate_appcast --download-url-prefix "$SITE/download/" --link "$SITE" --embed-release-notes \
    --maximum-deltas 0 "${APPCAST[@]}" "$FEED"

  gh release create "v$VERSION" "$DMG" "$DMG.sha256" --title "Hyperpoint $VERSION" --generate-notes \
    --target "$(git rev-parse HEAD)" "${PRERELEASE[@]}"
  r2put "${DMG:t}" --file "$DMG" --content-type application/x-apple-diskimage
  r2put "${DMG:t}.sha256" --file "$DMG.sha256" --content-type "text/plain; charset=utf-8"
  # The appcast and `latest` go after the DMG, so neither ever names a file that is not uploaded yet. A prerelease
  # leaves `latest` alone.
  r2put appcast.xml --file "$FEED/appcast.xml" --content-type "application/rss+xml; charset=utf-8"
  (( ${#PRERELEASE} )) || r2put latest --body "${DMG:t}" --content-type "text/plain; charset=utf-8"
  print "published $SITE/download/${DMG:t}"
fi
