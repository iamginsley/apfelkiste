#!/bin/zsh
# Builds a Developer ID signed, notarized DMG of Apfelkiste.
#
#   scripts/release.sh                 archive, export, DMG, notarize, staple
#   scripts/release.sh --skip-notarize  same without notarization (local testing only)
#
# One-time setup (Developer ID certificate, notarytool keychain profile): docs/release.md.
set -euo pipefail

cd "$(dirname "$0")/.."
NOTARY_PROFILE="${NOTARY_PROFILE:-apfelkiste}"
SKIP_NOTARIZE=false
[[ "${1:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=true

OUT=build/release
ARCHIVE=$OUT/Apfelkiste.xcarchive
rm -rf $OUT && mkdir -p $OUT

echo "▸ Generating project"
xcodegen generate --quiet

echo "▸ Running tests"
xcodebuild test -project Apfelkiste.xcodeproj -scheme Apfelkiste -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData -quiet

echo "▸ Archiving"
xcodebuild archive -project Apfelkiste.xcodeproj -scheme Apfelkiste -configuration Release \
  -destination 'generic/platform=macOS' -archivePath $ARCHIVE -allowProvisioningUpdates -quiet

echo "▸ Exporting with Developer ID"
xcodebuild -exportArchive -archivePath $ARCHIVE -exportPath $OUT/export \
  -exportOptionsPlist scripts/ExportOptions.plist -allowProvisioningUpdates -quiet

APP="$OUT/export/Apfelkiste.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
DMG=$OUT/Apfelkiste-$VERSION.dmg

echo "▸ Verifying signature ($VERSION, build $BUILD)"
codesign --verify --deep --strict --verbose=1 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID Application|TeamIdentifier=2567P974L9" >/dev/null \
  || { echo "✗ App is not signed with Developer ID of team 2567P974L9"; exit 1; }

echo "▸ Building DMG"
STAGING=$OUT/dmg
mkdir -p $STAGING && cp -R "$APP" $STAGING/ && ln -s /Applications $STAGING/Programme
hdiutil create -volname "Apfelkiste" -srcfolder $STAGING -fs HFS+ -format UDZO -ov $DMG -quiet
codesign --sign "Developer ID Application" --timestamp $DMG

if $SKIP_NOTARIZE; then
  echo "⚠ Skipped notarization: $DMG only runs on this Mac without a Gatekeeper warning."
  exit 0
fi

echo "▸ Notarizing (profile $NOTARY_PROFILE)"
xcrun notarytool submit $DMG --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple $DMG
spctl --assess --type open --context context:primary-signature --verbose $DMG

# Stable name for https://github.com/iamginsley/apfelkiste/releases/latest/download/Apfelkiste.dmg
cp $DMG $OUT/Apfelkiste.dmg
echo "✓ $DMG (upload $OUT/Apfelkiste.dmg to the release, the website links to it)"
