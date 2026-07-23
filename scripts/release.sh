#!/usr/bin/env bash
# Build, notarize, and staple a MacSweeper .app for direct download.
# Prerequisites:
#   - Xcode + XcodeGen
#   - Developer ID Application certificate in keychain
#   - DEVELOPMENT_TEAM set (10-char team ID)
#   - NOTARY_PROFILE set (keychain profile from `xcrun notarytool store-credentials`)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "error: set DEVELOPMENT_TEAM to your Apple Developer Team ID" >&2
  exit 1
fi
if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "error: set NOTARY_PROFILE (notarytool keychain profile name)" >&2
  exit 1
fi

command -v xcodegen >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)" >&2; exit 1; }

VERSION=$(grep -E 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*"\(.*\)"/\1/')
DIST="$ROOT/dist"
ARCHIVE="$DIST/MacSweeper.xcarchive"
APP_NAME="MacSweeper"
EXPORT_DIR="$DIST/export"
ZIP="$DIST/${APP_NAME}-${VERSION}.zip"

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Archiving Release (team $DEVELOPMENT_TEAM)"
xcodebuild \
  -scheme MacSweeper \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  archive

echo "==> Exporting Developer ID .app"
# ExportOptions for Developer ID distribution
EXPORT_PLIST="$DIST/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>${DEVELOPMENT_TEAM}</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

APP="$EXPORT_DIR/${APP_NAME}.app"
if [[ ! -d "$APP" ]]; then
  echo "error: expected $APP after export" >&2
  exit 1
fi

echo "==> Submitting for notarization"
# Zip for notarytool (directory submission also works on recent tools; zip is portable)
SUBMIT_ZIP="$DIST/submit-${APP_NAME}.zip"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Packaging release zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo ""
echo "Done. Release artifact:"
echo "  $ZIP"
echo "Upload to GitHub Releases (or your site). Free forever — no tip jar."
