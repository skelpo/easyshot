#!/bin/bash
set -e

APP_NAME="EasyShot"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
IDENTITY="Developer ID Application: Skelpo GmbH (K6UW5YV9F7)"

rm -rf "${APP_BUNDLE}"

mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

swiftc -O -target arm64-apple-macosx13.0 \
    -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}-arm64" \
    Sources/EasyShot/main.swift

swiftc -O -target x86_64-apple-macosx13.0 \
    -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}-x86_64" \
    Sources/EasyShot/main.swift

lipo -create \
    "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}-arm64" \
    "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}-x86_64" \
    -output "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

rm "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}-arm64" \
   "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}-x86_64"

cp Info.plist "${APP_BUNDLE}/Contents/"
cp EasyShot.icns "${APP_BUNDLE}/Contents/Resources/"

# Sign with a stable identity so macOS TCC (Files & Folders, Login Items,
# etc.) remembers permission grants across rebuilds. Without this the Swift
# linker's ad-hoc signature changes every build and the OS re-prompts.
if security find-identity -v -p codesigning | grep -q "${IDENTITY}"; then
    codesign --force --options runtime --sign "${IDENTITY}" "${APP_BUNDLE}"
else
    echo "WARN: '${IDENTITY}' not in keychain — falling back to ad-hoc sign."
    echo "      TCC permissions will reset on each rebuild."
    codesign --force --sign - "${APP_BUNDLE}"
fi

echo ""
echo "Built: ${APP_BUNDLE}"
echo ""
echo "To run:  open ${APP_BUNDLE}"
echo "To install: cp -r ${APP_BUNDLE} /Applications/"
echo ""
echo "RECOMMENDED: Disable macOS's built-in floating thumbnail so"
echo "screenshots are captured instantly by EasyShot:"
echo ""
echo "  defaults write com.apple.screencapture show-thumbnail -bool false && killall SystemUIServer"
echo ""
echo "To re-enable later:"
echo ""
echo "  defaults delete com.apple.screencapture show-thumbnail && killall SystemUIServer"
