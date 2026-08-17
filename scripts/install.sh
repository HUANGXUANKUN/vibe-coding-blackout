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

echo "==> Launching"
open "$TARGET"

echo ""
echo "Installed: $TARGET"
echo ""

if [ "$REPLACING_EXISTING" = true ]; then
    cat <<EOF
┌──────────────────────────────────────────────────────────────────────────┐
│  ⚠︎  RE-APPROVE ACCESSIBILITY                                            │
│                                                                          │
│  This replaced an existing install, so its ad-hoc signature changed and   │
│  the old Accessibility grant no longer applies. The checkbox may still    │
│  look ticked while the hotkey is dead.                                    │
│                                                                          │
│  System Settings ▸ Privacy & Security ▸ Accessibility                     │
│    → toggle $APP_NAME OFF, then ON again                                  │
│                                                                          │
│  Or reset it and approve fresh:                                          │
│    tccutil reset Accessibility $BUNDLE_ID
└──────────────────────────────────────────────────────────────────────────┘
EOF
else
    cat <<EOF
Grant Accessibility access to enable the double-tap gesture:
  System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable $APP_NAME

No restart needed — Blackout picks it up within a couple of seconds.
EOF
fi
