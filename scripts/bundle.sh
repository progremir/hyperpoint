#!/bin/zsh
# Builds Hyperpoint.app and installs it into ~/Applications (or $APP_DEST), quitting the running copy first.
set -euo pipefail
cd "${0:A:h}/.."

DEST="${APP_DEST:-$HOME/Applications}"
APP="$DEST/Hyperpoint.app"
STAGE_ROOT="$(mktemp -d)"
trap 'rm -rf "$STAGE_ROOT"' EXIT
STAGE="$STAGE_ROOT/Hyperpoint.app"

scripts/build-app.sh "$STAGE"

if pgrep -xq Hyperpoint; then
  osascript -e 'tell application id "dev.emir.hyperpoint" to quit' >/dev/null 2>&1 || true
  for _ in {1..30}; do pgrep -xq Hyperpoint || break; sleep 0.1; done
fi

mkdir -p "$DEST"
rm -rf "$APP"
mv "$STAGE" "$APP"
print "installed $APP"
