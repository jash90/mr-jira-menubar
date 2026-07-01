#!/usr/bin/env bash
# Build a distributable macOS .app bundle and a .dmg installer for MRJiraMenuBar.
# Usage: scripts/build-app.sh
set -euo pipefail

APP_NAME="MR Jira Menu Bar"
EXECUTABLE="MRJiraMenuBar"
BUNDLE_ID="com.raccoonsoftware.mrjiramenubar"
VERSION="1.1.0"
SHORT_VERSION="1.1.0"
MIN_MACOS="13.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG_STAGE="$DIST/dmg"
DMG="$DIST/${EXECUTABLE}-${VERSION}.dmg"

echo "==> Building release binary"
swift build -c release --package-path "$ROOT"
BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/$EXECUTABLE"
test -x "$BIN" || { echo "binary not found at $BIN" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>$EXECUTABLE</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>$MIN_MACOS</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# Sign with a real Developer ID Application certificate so the app runs on other
# Macs without Gatekeeper warnings. Override with SIGN_IDENTITY=<name or SHA-1>;
# if unset, auto-pick the first Developer ID Application identity in the Keychain
# by its SHA-1 hash (unique even when the cert name appears more than once).
# Falls back to ad-hoc signing when no Developer ID cert is present.
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Developer ID Application/{print $2; exit}')}"

if [ -n "$SIGN_IDENTITY" ]; then
  echo "==> Signing with: $SIGN_IDENTITY"
  # --options runtime (hardened runtime) + --timestamp are required for notarization.
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/$EXECUTABLE"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "==> No Developer ID cert found — ad-hoc signing (local use only)"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "   (codesign skipped)"
fi

echo "==> Building $DMG"
rm -rf "$DMG_STAGE" "$DMG"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DMG_STAGE"

# Notarize + staple so the DMG opens cleanly on other Macs (no "Apple cannot check
# it for malware" prompt). Needs a one-time notarytool keychain profile:
#   xcrun notarytool store-credentials mrjira-notary \
#     --apple-id you@example.com --team-id H2X8YGN869 --password <app-specific-pw>
# Override the profile name with NOTARY_PROFILE; skipped if it doesn't exist.
NOTARY_PROFILE="${NOTARY_PROFILE:-mrjira-notary}"
if [ -n "$SIGN_IDENTITY" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "==> Notarizing $DMG (profile: $NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
else
  echo "==> Skipping notarization (no '$NOTARY_PROFILE' notarytool profile)."
  echo "    Developer-ID-signed but un-notarized: others must right-click → Open once."
fi

echo
echo "Done."
echo "  App:  $APP"
echo "  DMG:  $DMG"
