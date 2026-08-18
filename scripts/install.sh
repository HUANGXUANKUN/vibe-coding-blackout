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

# Replacing an existing install invalidates the Accessibility grant, because an
# ad-hoc signature is keyed to the binary's cdhash and we just changed it. Worth
# shouting about: the symptom is a silently dead hotkey with the checkbox still
# ticked, which looks like a bug in the app.
REPLACING_EXISTING=false
[ -d "$TARGET" ] && REPLACING_EXISTING=true

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "==> Quitting the running instance"
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || pkill -x "$APP_NAME" || true
    sleep 1
fi

echo "==> Installing to $TARGET"
rm -rf "$TARGET"
cp -R "$ROOT/dist/$APP_NAME.app" "$TARGET"

# Leave no second copy behind: a stray dist/Blackout.app is the same build with
# the same signature, so double-clicking it in Finder silently starts a rival
# instance that fights this one over the displays.
rm -rf "$ROOT/dist"

echo "==> Launching"
open "$TARGET"

echo ""
echo "Installed: $TARGET"
echo ""

if [ "$REPLACING_EXISTING" = true ]; then
    cat <<EOF
  ⚠︎  RE-APPROVE ACCESSIBILITY

  This replaced an existing install, so the ad-hoc signature changed and the
  old grant no longer matches. The checkbox keeps looking ticked while the
  hotkey is dead, which reads as a bug in the app.

  Toggling the checkbox off and on does NOT reliably refresh it — the stale
  record stays pinned to the previous binary. Clear it, then approve fresh:

    tccutil reset Accessibility $BUNDLE_ID

  then open the pane and tick $APP_NAME:

    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

  No restart needed — $APP_NAME picks it up within a couple of seconds.

  To stop this happening on every install, sign with a stable identity:
    CODESIGN_IDENTITY="Your Identity" make install     (see README)
EOF
else
    cat <<EOF
Grant Accessibility access to enable the double-tap gesture:
  System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable $APP_NAME

No restart needed — Blackout picks it up within a couple of seconds.
EOF
fi
