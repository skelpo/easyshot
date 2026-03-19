#!/bin/bash
set -e

APP_NAME="EasyShot"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
IDENTITY="Developer ID Application: Skelpo GmbH (K6UW5YV9F7)"
NOTARY_PROFILE="EasyShot"

echo "==> Building..."
rm -rf "${APP_BUNDLE}" "${DMG_PATH}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

swiftc -O \
    -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" \
    Sources/EasyShot/main.swift

cp Info.plist "${APP_BUNDLE}/Contents/"

echo "==> Signing with hardened runtime..."
codesign --force --options runtime --timestamp \
    --sign "${IDENTITY}" "${APP_BUNDLE}"

echo "==> Verifying signature..."
codesign --verify --verbose=2 "${APP_BUNDLE}"
spctl --assess --type execute --verbose=2 "${APP_BUNDLE}"

echo "==> Creating DMG..."
DMG_STAGING="${BUILD_DIR}/dmg-staging"
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
cp -r "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO "${DMG_PATH}"
rm -rf "${DMG_STAGING}"

echo "==> Signing DMG..."
codesign --force --timestamp --sign "${IDENTITY}" "${DMG_PATH}"

echo "==> Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "${DMG_PATH}"

echo ""
echo "Done! Notarized DMG: ${DMG_PATH}"
echo ""
echo "Verify with:  spctl --assess --type open --verbose=2 ${DMG_PATH}"
