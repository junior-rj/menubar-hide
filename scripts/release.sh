#!/bin/bash
#
# release.sh — Build, sign (Developer ID), notarize and package MenubarHide as a DMG.
# Same flow as yourlaunch/scripts/release.sh; uses the team-wide notary profile.
#
# Uso:
#   ./scripts/release.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-yourlaunch-notary}"
APP_NAME="MenubarHide"
BUILD="build"

rm -rf "$BUILD"
mkdir -p "$BUILD"

xcodegen

echo "==> Arquivando (Release)"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -archivePath "$BUILD/$APP_NAME.xcarchive" archive

echo "==> Exportando com Developer ID"
xcodebuild -exportArchive \
  -archivePath "$BUILD/$APP_NAME.xcarchive" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$BUILD/export"

echo "==> Gerando DMG"
DMG="$BUILD/$APP_NAME.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$BUILD/export/$APP_NAME.app" -ov -format UDZO "$DMG"

echo "==> Notarizando o DMG (aguarda concluir)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Grampeando o ticket no DMG"
xcrun stapler staple "$DMG"

echo "==> Pronto: $DMG"
