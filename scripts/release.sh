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

# Documents é sincronizado (file provider) e re-marca o bundle com
# FinderInfo a qualquer momento — codesign --strict rejeita como detritus.
# Empacotar a partir de um staging fora da pasta sincronizada.
echo "==> Staging fora da pasta sincronizada"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/$APP_NAME-release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto --noextattr --norsrc "$BUILD/export/$APP_NAME.app" "$STAGING/$APP_NAME.app"

echo "==> Verificando assinatura e entitlements do app exportado"
codesign --verify --strict --deep "$STAGING/$APP_NAME.app"
codesign -d --entitlements - "$STAGING/$APP_NAME.app"

echo "==> Gerando DMG"
DMG="$STAGING/$APP_NAME.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING/$APP_NAME.app" -ov -format UDZO "$DMG"

echo "==> Assinando o DMG com a mesma Developer ID do app"
# capturar antes de filtrar: awk com exit fecha o pipe cedo e o pipefail
# transforma o SIGPIPE do codesign em falha do script
SIGN_INFO=$(codesign -d -vv "$STAGING/$APP_NAME.app" 2>&1)
IDENTITY=$(printf '%s\n' "$SIGN_INFO" | awk -F= '/^Authority=Developer ID Application/{print $2; exit}')
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "==> Notarizando o DMG (aguarda concluir)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Grampeando o ticket no DMG"
xcrun stapler staple "$DMG"

echo "==> Validando Gatekeeper no DMG final"
spctl -a -t open --context context:primary-signature -vv "$DMG"

FINAL_DMG="$BUILD/$APP_NAME.dmg"
cp "$DMG" "$FINAL_DMG"
echo "==> Pronto: $FINAL_DMG"
