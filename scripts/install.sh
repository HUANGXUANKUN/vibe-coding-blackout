#!/usr/bin/env bash
# Builds, installs to /Applications (or ~/Applications), and relaunches.
#
# Installing to a stable path matters: macOS ties the Accessibility grant to the
# app's location and signature, so moving the bundle around means re-approving it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Blackout"
BUNDLE_ID="com.huangxuankun.blackout"

"$ROOT/scripts/bundle.sh"

if [ -w /Applications ]; then
    TARGET_DIR="/Applications"
else
    TARGET_DIR="$HOME/Applications"
    mkdir -p "$TARGET_DIR"
fi
TARGET="$TARGET_DIR/$APP_NAME.app"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "==> Quitting the running instance"
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || pkill -x "$APP_NAME" || true
    sleep 1
fi

echo "==> Installing to $TARGET"
rm -rf "$TARGET"
cp -R "$ROOT/dist/$APP_NAME.app" "$TARGET"

echo "==> Launching"
open "$TARGET"

cat <<EOF

Installed: $TARGET

If the double-tap gesture does nothing, grant Accessibility access:
  System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable $APP_NAME

Rebuilding changes the ad-hoc signature, so macOS may ask again after an update.
If the toggle is already on but stale, turn it off and on again, or run:
  tccutil reset Accessibility $BUNDLE_ID
EOF
