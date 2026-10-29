#!/bin/zsh
# Builds the development app, Hyperpoint Dev, and installs it into ~/Applications (or $APP_DEST), quitting the running
# copy of it first. The release, Hyperpoint.app, is a separate app and stays as it is.
set -euo pipefail
cd "${0:A:h}/.."

DEST="${APP_DEST:-$HOME/Applications}"
APP="$DEST/Hyperpoint Dev.app"
STAGE_ROOT="$(mktemp -d)"
trap 'rm -rf "$STAGE_ROOT"' EXIT
STAGE="$STAGE_ROOT/Hyperpoint Dev.app"

scripts/build-app.sh "$STAGE"

if pgrep -fq "$APP/Contents/MacOS/Hyperpoint"; then
  osascript -e 'tell application id "dev.emir.hyperpoint.dev" to quit' >/dev/null 2>&1 || true
  for _ in {1..30}; do pgrep -fq "$APP/Contents/MacOS/Hyperpoint" || break; sleep 0.1; done
fi

mkdir -p "$DEST"
rm -rf "$APP"
mv "$STAGE" "$APP"
print "installed $APP"
