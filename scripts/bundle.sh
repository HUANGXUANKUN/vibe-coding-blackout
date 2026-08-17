#!/usr/bin/env bash
# Assembles dist/Blackout.app from the SwiftPM binary.
#
# There is no Xcode project on purpose: Package.swift plus this script is
# reviewable, and the whole thing builds with only the Command Line Tools.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="Blackout"
BUNDLE_ID="com.huangxuankun.blackout"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

cd "$ROOT"
echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --product blackout

BIN="$(swift build -c "$CONFIG" --show-bin-path)/blackout"
VERSION="$("$BIN" --version)"
echo "==> Version $VERSION"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# LSUIElement: menu-bar only, no Dock tile, no app switcher entry.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>              <string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
	<key>CFBundleExecutable</key>        <string>$APP_NAME</string>
	<key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
	<key>CFBundlePackageType</key>       <string>APPL</string>
	<key>CFBundleSignature</key>         <string>????</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key>           <string>$VERSION</string>
	<key>CFBundleIconFile</key>          <string>$APP_NAME</string>
	<key>LSMinimumSystemVersion</key>    <string>13.0</string>
	<key>LSUIElement</key>               <true/>
	<key>NSHighResolutionCapable</key>   <true/>
	<key>NSSupportsAutomaticTermination</key>   <false/>
	<key>NSSupportsSuddenTermination</key>      <false/>
	<key>NSHumanReadableCopyright</key>  <string>MIT licensed</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Icon"
ICONSET="$(mktemp -d)/$APP_NAME.iconset"
if "$BIN" --emit-iconset "$ICONSET" 2>/dev/null &&
   iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$APP_NAME.icns" 2>/dev/null; then
    echo "    embedded $APP_NAME.icns"
else
    # Non-fatal: the app is menu-bar only, the icon is cosmetic.
    echo "    skipped (icon generation unavailable here)"
fi

# TCC identifies the app by its signature, so this has to exist or Accessibility
# approval will not stick at all.
#
# The default is ad-hoc, which pins the grant to the binary's cdhash: every
# rebuild silently invalidates it. Set CODESIGN_IDENTITY to a stable identity
# (self-signed or Developer ID) and the grant survives rebuilds instead —
# see "Known limits" in the README.
IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    echo "==> Signing (ad-hoc)"
else
    echo "==> Signing as: $IDENTITY"
fi
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP" >/dev/null 2>&1 \
    || { echo "    codesign failed"; exit 1; }
codesign --verify --deep --strict "$APP" && echo "    signature verified"

echo ""
echo "Built $APP"
